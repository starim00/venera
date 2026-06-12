part of 'reader.dart';

class _PageTranslationSheet extends StatefulWidget {
  const _PageTranslationSheet({required this.reader});

  final _ReaderState reader;

  @override
  State<_PageTranslationSheet> createState() => _PageTranslationSheetState();
}

class _PageTranslationSheetState extends State<_PageTranslationSheet> {
  bool loading = true;
  String? error;
  TranslationResult? result;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => translate());
  }

  Future<void> translate({bool forceRefresh = false}) async {
    final reader = widget.reader;
    final indices =
        reader._imageViewController?.getCurrentPageImageIndices() ??
        const <int>[];
    if (indices.isEmpty || reader.images == null) {
      setState(() {
        loading = false;
        error = "No Image".tl;
      });
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    try {
      final service = TranslationService();
      final translated = await service.translatePage(
        sourceKey: reader.type.sourceKey,
        comicId: reader.cid,
        epId: reader.eid,
        startPage: indices.first + 1,
        endPage: indices.last + 1,
        imageKeys: indices.map((i) => reader.images![i]).toList(),
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;
      setState(() {
        result = translated;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = _readableError(e);
      });
    }
  }

  String _readableError(Object error) {
    final message = error.toString();
    if (message.contains('InvalidCertificate') ||
        message.contains('Invalid certificate') ||
        message.contains('UnknownIssuer')) {
      return "The translation endpoint certificate is not trusted. Enable Ignore Certificate Errors in Page Translation settings, or configure a trusted HTTPS certificate."
          .tl;
    }
    return message;
  }

  void copyTranslation() {
    final text = result?.toText() ?? '';
    if (text.isEmpty) {
      return;
    }
    Clipboard.setData(ClipboardData(text: text));
    context.showMessage(message: "Copied".tl);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text("Page Translation".tl, style: ts.s18),
                const Spacer(),
                IconButton(
                  tooltip: "Copy Translation".tl,
                  onPressed: result == null || result!.items.isEmpty
                      ? null
                      : copyTranslation,
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  tooltip: "Retranslate".tl,
                  onPressed: loading
                      ? null
                      : () => translate(forceRefresh: true),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: "Close".tl,
                  onPressed: context.pop,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(child: buildBody()),
          ],
        ),
      ),
    );
  }

  Widget buildBody() {
    if (loading) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text("Translating current page...".tl),
            ],
          ),
        ),
      );
    }

    if (error != null) {
      return SizedBox(
        height: 220,
        child: NetworkError(
          message: error!,
          retry: () => translate(forceRefresh: true),
        ),
      );
    }

    final items = result?.items ?? const <TranslationItem>[];
    if (items.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(child: Text("No text was found on this page".tl)),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.62,
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(color: context.colorScheme.outlineVariant),
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.original.isNotEmpty)
                  Text(
                    item.original,
                    style: ts.s12.withColor(context.colorScheme.outline),
                  ),
                if (item.original.isNotEmpty) const SizedBox(height: 6),
                Text(item.translated, style: ts.s16),
                if (item.note?.isNotEmpty == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    item.note!,
                    style: ts.s12.withColor(context.colorScheme.outline),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
