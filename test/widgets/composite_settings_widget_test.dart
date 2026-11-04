import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_vibrance/theme/app_themes.dart';
import 'package:open_vibrance/transcription/composite_config.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/composite_settings_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('default slots, key hints, add slot, shared OpenRouter key', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      StorageKey.googleApiKey.key: 'stale-key',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.buildThemeData(AppThemes.dark, AppThemeMode.dark),
        home: const Scaffold(
          body: SingleChildScrollView(child: CompositeSettingsWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('GPT Live Transcribe'), findsOneWidget);
    expect(find.text('Gemini 3.5 Flash'), findsOneWidget);
    expect(find.text('DeepSeek V4.1 Flash'), findsOneWidget);
    expect(find.text('Configure API key in OpenAI settings'), findsOneWidget);
    final keyField = tester.widget<TextField>(find.byType(TextField));
    expect(keyField.obscureText, isTrue);
    expect(keyField.controller!.text, 'stale-key');

    await tester.tap(find.text('Add Provider'));
    await tester.pumpAndSettle();
    expect(find.text('Slot 3'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'fresh-key');
    await tester.pumpAndSettle();

    const storage = FlutterSecureStorage();
    expect(
      CompositeConfig.decodeSlots(
        await storage.read(key: StorageKey.compositeSlots.key),
      ),
      hasLength(3),
    );
    for (final key in [StorageKey.openRouterApiKey, StorageKey.googleApiKey]) {
      expect(await storage.read(key: key.key), 'fresh-key');
    }
  });
}
