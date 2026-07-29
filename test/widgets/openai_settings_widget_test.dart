import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/theme/app_themes.dart';
import 'package:open_vibrance/transcription/openai_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/openai_settings_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows and persists both new OpenAI transcription models', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      StorageKey.openAiApiKey.key: 'saved-openai-key',
      StorageKey.openAiModel.key: OpenAIModel.gptLiveTranscribe.modelId,
    });

    await _pumpSettings(tester);

    expect(find.text('GPT Live Transcribe'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton2<OpenAIModel>));
    await tester.pumpAndSettle();

    expect(find.text('GPT Transcribe'), findsOneWidget);
    expect(find.text('GPT Live Transcribe'), findsNWidgets(2));

    await tester.tap(find.text('GPT Transcribe'));
    await tester.pumpAndSettle();

    const storage = FlutterSecureStorage();
    expect(
      await storage.read(key: StorageKey.openAiModel.key),
      OpenAIModel.gptTranscribe.modelId,
    );
    expect(
      await storage.read(key: StorageKey.openAiApiKey.key),
      'saved-openai-key',
    );
  });
}

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.buildThemeData(AppThemes.dark, AppThemeMode.dark),
      home: const Scaffold(
        body: SingleChildScrollView(child: OpenAiSettingsWidget()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
