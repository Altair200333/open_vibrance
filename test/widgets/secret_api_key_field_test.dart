import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:open_vibrance/theme/app_themes.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/widgets/provider_settings/openai_settings_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('saved API key is masked until the eye is tapped', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(<String, String>{
      StorageKey.openAiApiKey.key: 'sk-secret',
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemes.buildThemeData(AppThemes.dark, AppThemeMode.dark),
        home: const Scaffold(
          body: SingleChildScrollView(child: OpenAiSettingsWidget()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    TextField keyField() =>
        tester.widget<TextField>(find.byType(TextField).first);
    expect(keyField().controller!.text, 'sk-secret');
    expect(keyField().obscureText, isTrue);
    expect(keyField().enableSuggestions, isFalse);

    await tester.tap(find.byIcon(LucideIcons.eye));
    await tester.pump();
    expect(keyField().obscureText, isFalse);

    await tester.tap(find.byIcon(LucideIcons.eyeOff));
    await tester.pump();
    expect(keyField().obscureText, isTrue);
  });
}
