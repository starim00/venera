part of 'settings_page.dart';

class _TranslationSettingsPage extends StatefulWidget {
  const _TranslationSettingsPage();

  @override
  State<_TranslationSettingsPage> createState() =>
      _TranslationSettingsPageState();
}

class _TranslationSettingsPageState extends State<_TranslationSettingsPage> {
  late final TextEditingController endpointController;
  late final TextEditingController apiKeyController;
  late final TextEditingController modelController;
  late final TextEditingController promptController;
  late final TextEditingController defaultPromptController;
  late String targetLanguage;

  @override
  void initState() {
    super.initState();
    endpointController = TextEditingController(
      text: appdata.settings['translationEndpoint'],
    );
    apiKeyController = TextEditingController(
      text: appdata.settings['translationApiKey'],
    );
    modelController = TextEditingController(
      text: appdata.settings['translationModel'],
    );
    promptController = TextEditingController(
      text: appdata.settings['translationSystemPrompt'],
    );
    defaultPromptController = TextEditingController(
      text: defaultTranslationSystemPrompt.trim(),
    );
    targetLanguage = appdata.settings['translationTargetLanguage'] ?? 'system';
  }

  @override
  void dispose() {
    endpointController.dispose();
    apiKeyController.dispose();
    modelController.dispose();
    promptController.dispose();
    defaultPromptController.dispose();
    super.dispose();
  }

  void save() {
    appdata.settings['translationEndpoint'] = endpointController.text.trim();
    appdata.settings['translationApiKey'] = apiKeyController.text.trim();
    appdata.settings['translationModel'] = modelController.text.trim();
    appdata.settings['translationTargetLanguage'] = targetLanguage;
    appdata.settings['translationSystemPrompt'] = promptController.text.trim();
    appdata.saveData();
    context.showMessage(message: "Saved".tl);
  }

  Future<void> clearCache() async {
    await TranslationCache().clear();
    if (mounted) {
      context.showMessage(message: "Translation cache cleared".tl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(
          title: Text("Page Translation".tl),
          actions: [TextButton(onPressed: save, child: Text("Save".tl))],
        ),
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                "Images are sent only when you manually translate the current reader page."
                    .tl,
                style: ts.s12,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: endpointController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Translation Endpoint".tl,
                  helperText:
                      "OpenAI-compatible endpoint, such as https://api.openai.com"
                          .tl,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apiKeyController,
                obscureText: true,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "API Key".tl,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelController,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Translation Model".tl,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: targetLanguage,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Target Language".tl,
                ),
                items: [
                  DropdownMenuItem(value: 'system', child: Text("System".tl)),
                  const DropdownMenuItem(value: 'zh-CN', child: Text('zh-CN')),
                  const DropdownMenuItem(value: 'zh-TW', child: Text('zh-TW')),
                  const DropdownMenuItem(value: 'en-US', child: Text('en-US')),
                  const DropdownMenuItem(value: 'ja-JP', child: Text('ja-JP')),
                  const DropdownMenuItem(value: 'ko-KR', child: Text('ko-KR')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      targetLanguage = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Custom System Prompt".tl,
                  helperText: "Leave empty to use the default prompt".tl,
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    promptController.clear();
                    context.showMessage(message: "Default prompt restored".tl);
                  },
                  icon: const Icon(Icons.restore),
                  label: Text("Restore Default Prompt".tl),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: defaultPromptController,
                readOnly: true,
                minLines: 5,
                maxLines: 10,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: "Default System Prompt".tl,
                ),
              ),
              const SizedBox(height: 16),
              _SwitchSetting(
                title: "Ignore Certificate Errors".tl,
                subtitle:
                    "Use this only for self-hosted endpoints with untrusted certificates."
                        .tl,
                settingKey: "ignoreBadCertificate",
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: clearCache,
                icon: const Icon(Icons.delete_outline),
                label: Text("Clear Translation Cache".tl),
              ),
            ],
          ).padding(const EdgeInsets.all(16)),
        ),
      ],
    );
  }
}
