import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/translation.dart';

void main() {
  group('TranslationResult', () {
    test('parses valid JSON result', () {
      final result = TranslationResult.parse('''
      {
        "sourceLanguage": "ja",
        "targetLanguage": "zh-CN",
        "items": [
          {
            "order": 1,
            "original": "こんにちは",
            "translated": "你好"
          }
        ]
      }
      ''');

      expect(result.sourceLanguage, 'ja');
      expect(result.targetLanguage, 'zh-CN');
      expect(result.items.single.translated, '你好');
    });

    test('throws on invalid JSON', () {
      expect(
        () => TranslationResult.parse('not json'),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts empty items', () {
      final result = TranslationResult.parse('''
      {
        "sourceLanguage": "unknown",
        "targetLanguage": "zh-CN",
        "items": []
      }
      ''');

      expect(result.items, isEmpty);
    });
  });

  group('TranslationCache', () {
    late Directory dir;
    late TranslationCache cache;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('venera_translation_test');
      cache = TranslationCache.forTesting('${dir.path}/translation_cache.db');
    });

    tearDown(() async {
      cache.close();
      await dir.delete(recursive: true);
    });

    test('reads cached result by key', () async {
      const result = TranslationResult(
        sourceLanguage: 'ja',
        targetLanguage: 'zh-CN',
        items: [TranslationItem(order: 1, original: 'a', translated: 'b')],
      );

      await cache.write('key-a', result);
      final cached = await cache.read('key-a');

      expect(cached?.items.single.translated, 'b');
    });

    test('different image hash produces different cache key', () {
      final key1 = TranslationService.buildCacheKey(
        sourceKey: 'source',
        comicId: 'comic',
        epId: 'ep',
        startPage: 1,
        endPage: 1,
        imageHash: 'hash-a',
        targetLanguage: 'zh-CN',
        model: 'model',
      );
      final key2 = TranslationService.buildCacheKey(
        sourceKey: 'source',
        comicId: 'comic',
        epId: 'ep',
        startPage: 1,
        endPage: 1,
        imageHash: 'hash-b',
        targetLanguage: 'zh-CN',
        model: 'model',
      );

      expect(key1, isNot(key2));
    });
  });

  test('translatePage sends OpenAI-compatible multimodal request', () async {
    final dir = await Directory.systemTemp.createTemp(
      'venera_translation_test',
    );
    final cache = TranslationCache.forTesting(
      '${dir.path}/translation_cache.db',
    );
    final image = File('${dir.path}/page.jpg');
    await image.writeAsBytes(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00]));
    final adapter = _FakeAdapter();

    appdata.settings['translationEndpoint'] = 'https://example.com';
    appdata.settings['translationApiKey'] = 'secret-key';
    appdata.settings['translationModel'] = 'vision-model';
    appdata.settings['translationTargetLanguage'] = 'zh-CN';
    appdata.settings['translationSystemPrompt'] = '';

    final service = TranslationService(
      cache: cache,
      dioFactory: (options) => Dio(options)..httpClientAdapter = adapter,
    );

    final result = await service.translatePage(
      sourceKey: 'local',
      comicId: 'comic',
      epId: 'ep',
      startPage: 1,
      endPage: 1,
      imageKeys: ['file://${image.path}'],
    );

    expect(result.items.single.translated, '你好');
    expect(
      adapter.options?.uri.toString(),
      'https://example.com/v1/chat/completions',
    );
    expect(adapter.options?.headers['Authorization'], 'Bearer secret-key');
    expect(adapter.options?.extra['maskDataInLog'], true);
    expect(
      adapter.options?.extra['maskHeadersInLog'],
      contains('Authorization'),
    );
    expect(
      jsonEncode(adapter.options?.data),
      contains('data:image/jpeg;base64'),
    );

    cache.close();
    await dir.delete(recursive: true);
  });
}

class _FakeAdapter implements HttpClientAdapter {
  RequestOptions? options;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    this.options = options;
    return ResponseBody.fromString(
      jsonEncode({
        'choices': [
          {
            'message': {
              'content': jsonEncode({
                'sourceLanguage': 'ja',
                'targetLanguage': 'zh-CN',
                'items': [
                  {'order': 1, 'original': 'こんにちは', 'translated': '你好'},
                ],
              }),
            },
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
