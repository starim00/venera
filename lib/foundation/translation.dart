import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/network/images.dart';
import 'package:venera/utils/io.dart';

const defaultTranslationSystemPrompt = '''
You are translating manga/comic page images for a reader app.
Read all visible dialogue, narration, sound effects, and important signs in the provided image(s).
Return strict JSON only. Do not wrap it in markdown.
Keep the reading order natural for the page.
If text is unreadable, omit it instead of guessing.
Schema:
{
  "sourceLanguage": "detected language code or unknown",
  "targetLanguage": "target language code",
  "items": [
    {
      "order": 1,
      "original": "source text",
      "translated": "translated text",
      "speaker": null,
      "note": null
    }
  ]
}
''';

class TranslationItem {
  const TranslationItem({
    required this.order,
    required this.original,
    required this.translated,
    this.speaker,
    this.note,
  });

  final int order;
  final String original;
  final String translated;
  final String? speaker;
  final String? note;

  factory TranslationItem.fromJson(
    Map<String, dynamic> json,
    int fallbackOrder,
  ) {
    return TranslationItem(
      order: (json['order'] as num?)?.toInt() ?? fallbackOrder,
      original: json['original']?.toString() ?? '',
      translated: json['translated']?.toString() ?? '',
      speaker: json['speaker']?.toString(),
      note: json['note']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'order': order,
    'original': original,
    'translated': translated,
    if (speaker != null) 'speaker': speaker,
    if (note != null) 'note': note,
  };
}

class TranslationResult {
  const TranslationResult({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.items,
  });

  final String sourceLanguage;
  final String targetLanguage;
  final List<TranslationItem> items;

  factory TranslationResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw const FormatException('Translation response is missing items.');
    }
    return TranslationResult(
      sourceLanguage: json['sourceLanguage']?.toString() ?? 'unknown',
      targetLanguage: json['targetLanguage']?.toString() ?? '',
      items: [
        for (var i = 0; i < rawItems.length; i++)
          if (rawItems[i] is Map)
            TranslationItem.fromJson(
              Map<String, dynamic>.from(rawItems[i] as Map),
              i + 1,
            ),
      ],
    );
  }

  static TranslationResult parse(String content) {
    final cleaned = _stripMarkdownFence(content.trim());
    final json = jsonDecode(cleaned);
    if (json is! Map) {
      throw const FormatException('Translation response is not a JSON object.');
    }
    return TranslationResult.fromJson(Map<String, dynamic>.from(json));
  }

  static String _stripMarkdownFence(String text) {
    if (!text.startsWith('```')) {
      return text;
    }
    final lines = LineSplitter.split(text).toList();
    if (lines.length >= 3 && lines.last.trim() == '```') {
      return lines.sublist(1, lines.length - 1).join('\n');
    }
    return text;
  }

  Map<String, dynamic> toJson() => {
    'sourceLanguage': sourceLanguage,
    'targetLanguage': targetLanguage,
    'items': items.map((e) => e.toJson()).toList(),
  };

  String toText() {
    return items.map((e) => e.translated).where((e) => e.isNotEmpty).join('\n');
  }
}

class TranslationRequestImage {
  const TranslationRequestImage({
    required this.imageKey,
    required this.page,
    required this.bytes,
  });

  final String imageKey;
  final int page;
  final Uint8List bytes;
}

class TranslationCache {
  TranslationCache._(this._db);

  static TranslationCache? _instance;

  final Database _db;

  factory TranslationCache() {
    return _instance ??= TranslationCache._(
      _openDatabase('${App.dataPath}/translation_cache.db'),
    );
  }

  @visibleForTesting
  factory TranslationCache.forTesting(String path) {
    return TranslationCache._(_openDatabase(path));
  }

  static Database _openDatabase(String path) {
    final db = sqlite3.open(path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS translation_cache (
        key TEXT PRIMARY KEY NOT NULL,
        value TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    return db;
  }

  Future<TranslationResult?> read(String key) async {
    final res = _db.select(
      'SELECT value FROM translation_cache WHERE key = ?',
      [key],
    );
    if (res.isEmpty) {
      return null;
    }
    return TranslationResult.fromJson(
      Map<String, dynamic>.from(jsonDecode(res.first['value'] as String)),
    );
  }

  Future<void> write(String key, TranslationResult result) async {
    _db.execute(
      '''
      INSERT OR REPLACE INTO translation_cache (key, value, created_at)
      VALUES (?, ?, ?)
      ''',
      [key, jsonEncode(result.toJson()), DateTime.now().millisecondsSinceEpoch],
    );
  }

  Future<void> delete(String key) async {
    _db.execute('DELETE FROM translation_cache WHERE key = ?', [key]);
  }

  Future<void> clear() async {
    _db.execute('DELETE FROM translation_cache');
  }

  void close() {
    _db.dispose();
  }
}

typedef TranslationDioFactory = Dio Function(BaseOptions options);

class TranslationService {
  TranslationService({
    TranslationCache? cache,
    TranslationDioFactory? dioFactory,
  }) : _cache = cache ?? TranslationCache(),
       _dioFactory = dioFactory ?? ((options) => AppDio(options));

  final TranslationCache _cache;
  final TranslationDioFactory _dioFactory;

  bool get isConfigured {
    return _settingString('translationEndpoint').isNotEmpty &&
        _settingString('translationApiKey').isNotEmpty &&
        _settingString('translationModel').isNotEmpty;
  }

  Future<TranslationResult> translatePage({
    required String sourceKey,
    required String comicId,
    required String epId,
    required int startPage,
    required int endPage,
    required List<String> imageKeys,
    bool forceRefresh = false,
  }) async {
    if (!isConfigured) {
      throw StateError('Translation service is not configured.');
    }

    final images = <TranslationRequestImage>[];
    for (var i = 0; i < imageKeys.length; i++) {
      images.add(
        TranslationRequestImage(
          imageKey: imageKeys[i],
          page: startPage + i,
          bytes: await loadImageBytes(
            imageKeys[i],
            sourceKey: sourceKey,
            comicId: comicId,
            epId: epId,
          ),
        ),
      );
    }

    final model = _settingString('translationModel');
    final targetLanguage = currentTranslationTargetLanguage;
    final cacheKey = buildCacheKey(
      sourceKey: sourceKey,
      comicId: comicId,
      epId: epId,
      startPage: startPage,
      endPage: endPage,
      imageHash: hashImages(images.map((e) => e.bytes)),
      targetLanguage: targetLanguage,
      model: model,
    );

    if (!forceRefresh) {
      final cached = await _cache.read(cacheKey);
      if (cached != null) {
        return cached;
      }
    } else {
      await _cache.delete(cacheKey);
    }

    final result = await _requestTranslation(
      images: images,
      targetLanguage: targetLanguage,
      model: model,
    );
    await _cache.write(cacheKey, result);
    return result;
  }

  Future<Uint8List> loadImageBytes(
    String imageKey, {
    required String sourceKey,
    required String comicId,
    required String epId,
  }) async {
    if (imageKey.startsWith('file://')) {
      return File(imageKey.substring(7)).readAsBytes();
    }

    Uint8List? imageBytes;
    await for (final progress in ImageDownloader.loadComicImage(
      imageKey,
      sourceKey,
      comicId,
      epId,
    )) {
      if (progress.imageBytes != null) {
        imageBytes = progress.imageBytes;
        break;
      }
    }
    if (imageBytes == null) {
      throw StateError('Image data is empty.');
    }
    return imageBytes;
  }

  Future<TranslationResult> _requestTranslation({
    required List<TranslationRequestImage> images,
    required String targetLanguage,
    required String model,
  }) async {
    final endpoint = normalizeEndpoint(_settingString('translationEndpoint'));
    final apiKey = _settingString('translationApiKey');
    final dio = _dioFactory(
      BaseOptions(
        method: 'POST',
        responseType: ResponseType.json,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final res = await dio.post<dynamic>(
      endpoint,
      data: buildRequestBody(
        images: images,
        targetLanguage: targetLanguage,
        model: model,
        systemPrompt: _settingString('translationSystemPrompt').isEmpty
            ? defaultTranslationSystemPrompt
            : _settingString('translationSystemPrompt'),
      ),
      options: Options(
        extra: {
          'maskHeadersInLog': ['Authorization'],
          'maskDataInLog': true,
        },
      ),
    );

    final statusCode = res.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 300) {
      throw StateError('Translation request failed: HTTP $statusCode');
    }

    final content = extractContent(res.data);
    return TranslationResult.parse(content);
  }

  @visibleForTesting
  static Map<String, dynamic> buildRequestBody({
    required List<TranslationRequestImage> images,
    required String targetLanguage,
    required String model,
    required String systemPrompt,
  }) {
    return {
      'model': model,
      'response_format': {'type': 'json_object'},
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': [
            {
              'type': 'text',
              'text':
                  'Translate this comic page to $targetLanguage. Return JSON only.',
            },
            for (final image in images)
              {
                'type': 'image_url',
                'image_url': {
                  'url':
                      'data:${detectMimeType(image.bytes)};base64,${base64Encode(image.bytes)}',
                },
              },
          ],
        },
      ],
    };
  }

  @visibleForTesting
  static String extractContent(dynamic data) {
    if (data is String) {
      data = jsonDecode(data);
    }
    if (data is! Map) {
      throw const FormatException('Translation response is not an object.');
    }
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const FormatException('Translation response is missing choices.');
    }
    final first = choices.first;
    if (first is! Map) {
      throw const FormatException('Translation choice is invalid.');
    }
    final message = first['message'];
    if (message is! Map) {
      throw const FormatException('Translation message is invalid.');
    }
    final content = message['content'];
    if (content is String) {
      return content;
    }
    if (content is List) {
      return content
          .whereType<Map>()
          .map((e) => e['text'])
          .whereType<String>()
          .join('\n');
    }
    throw const FormatException('Translation content is invalid.');
  }

  @visibleForTesting
  static String buildCacheKey({
    required String sourceKey,
    required String comicId,
    required String epId,
    required int startPage,
    required int endPage,
    required String imageHash,
    required String targetLanguage,
    required String model,
  }) {
    return [
      'page_translation_v1',
      sourceKey,
      comicId,
      epId,
      '$startPage-$endPage',
      imageHash,
      targetLanguage,
      model,
    ].join('@');
  }

  @visibleForTesting
  static String hashImages(Iterable<Uint8List> images) {
    final bytes = BytesBuilder(copy: false);
    for (final image in images) {
      bytes.add(image);
    }
    return sha256.convert(bytes.takeBytes()).toString();
  }

  @visibleForTesting
  static String detectMimeType(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'GIF') {
      return 'image/gif';
    }
    return 'image/jpeg';
  }

  @visibleForTesting
  static String normalizeEndpoint(String endpoint) {
    endpoint = endpoint.trim();
    if (endpoint.endsWith('/chat/completions')) {
      return endpoint;
    }
    if (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (endpoint.endsWith('/v1')) {
      return '$endpoint/chat/completions';
    }
    return '$endpoint/v1/chat/completions';
  }
}

String get currentTranslationTargetLanguage {
  final setting = _settingString('translationTargetLanguage');
  if (setting.isNotEmpty && setting != 'system') {
    return setting;
  }
  final locale = App.locale;
  if (locale.languageCode == 'zh') {
    return locale.countryCode == 'TW' ? 'zh-TW' : 'zh-CN';
  }
  if (locale.countryCode == null) {
    return locale.languageCode;
  }
  return '${locale.languageCode}-${locale.countryCode}';
}

String _settingString(String key) {
  return appdata.settings[key]?.toString().trim() ?? '';
}
