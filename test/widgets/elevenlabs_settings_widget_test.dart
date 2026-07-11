import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/theme/app_themes.dart';
import 'package:open_vibrance/transcription/elevenlabs_transcription_provider.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/elevenlabs_settings_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('hides filtering controls for non-realtime ElevenLabs models', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({
      StorageKey.elevenLabsModel.key: ElevenLabsModel.scribeV2.modelId,
      StorageKey.elevenLabsRealtimeFilteringEnabled.key: 'true',
      StorageKey.openRouterApiKey.key: 'saved-key',
    });

    await _pumpSettings(tester);

    expect(find.text('Enable Transcription Filtering'), findsNothing);
    expect(find.text('OpenRouter API key'), findsNothing);
  });

  testWidgets(
    'reveals an obscured OpenRouter key field when filtering is enabled',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({
        StorageKey.elevenLabsModel.key:
            ElevenLabsModel.scribeV2Realtime.modelId,
      });

      await _pumpSettings(tester);

      expect(find.text('Enable Transcription Filtering'), findsOneWidget);
      expect(find.text('OpenRouter API key'), findsNothing);

      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      expect(find.text('OpenRouter API key'), findsOneWidget);
      final keyField = tester.widget<TextField>(find.byType(TextField).last);
      expect(keyField.obscureText, isTrue);
      expect(keyField.enableSuggestions, isFalse);
      expect(keyField.autocorrect, isFalse);

      await tester.enterText(find.byType(TextField).last, 'partial-key');
      await tester.enterText(find.byType(TextField).last, 'openrouter-key');
      await tester.pumpAndSettle();

      const storage = FlutterSecureStorage();
      expect(
        await storage.read(
          key: StorageKey.elevenLabsRealtimeFilteringEnabled.key,
        ),
        'true',
      );
      expect(
        await storage.read(key: StorageKey.openRouterApiKey.key),
        'openrouter-key',
      );
    },
  );
}

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemes.buildThemeData(AppThemes.dark, AppThemeMode.dark),
      home: const Scaffold(
        body: SingleChildScrollView(child: ElevenLabsSettingsWidget()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
