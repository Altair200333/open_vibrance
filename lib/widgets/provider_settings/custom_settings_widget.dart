import 'package:flutter/material.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/theme/app_color_theme.dart';
import 'package:open_vibrance/widgets/constants.dart';
import 'package:open_vibrance/transcription/types.dart';

class CustomSettingsWidget extends StatefulWidget {
  const CustomSettingsWidget({super.key});

  @override
  State<CustomSettingsWidget> createState() => _CustomSettingsWidgetState();
}

class _CustomSettingsWidgetState extends State<CustomSettingsWidget> {
  final TextEditingController _customJSCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomJSCode();
  }

  Future<void> _loadCustomJSCode() async {
    final code = await SecureStorageService().readValue(
      StorageKey.customPythonScript.key,
    );
    if (code != null && mounted) {
      setState(() {
        _customJSCodeController.text = code;
      });
    }
  }

  @override
  void dispose() {
    _customJSCodeController.dispose();
    super.dispose();
  }

  void _onCustomJSCodeChanged(String value) {
    SecureStorageService().saveValue(StorageKey.customPythonScript.key, value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Python code',
          style: TextStyle(color: colors.textSecondary, fontSize: kFontSizeMd, fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        Text.rich(
          TextSpan(
            style: TextStyle(color: colors.textHint, fontSize: kFontSizeSm),
            children: [
              TextSpan(
                text:
                    'Enter custom Python code to be executed for transcription.\n\n',
              ),
              TextSpan(
                text: '- Make sure you have python installed in the system\n',
              ),
              TextSpan(
                text: '- The script should read audio from global variable ',
              ),
              TextSpan(
                text: 'base64_audio',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: ' which is a base64 encoded audio\n'),
              TextSpan(text: '- The code should '),
              TextSpan(
                text: 'print',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(
                text: ' final transcription as a string (app will read stdout)',
              ),
            ],
          ),
        ),
        SizedBox(height: 8),
        Text(
          'If unsure what this means, just paste docs from your transcription provider into ChatGPT and ask to write Python snippet accepting base64 audio and returning a string from it',
          style: TextStyle(color: colors.textSecondary, fontSize: kFontSizeSm, fontStyle: FontStyle.italic),
        ),
        SizedBox(height: 16),
        TextField(
          controller: _customJSCodeController,
          decoration: InputDecoration(hintText: 'Plain Python code'),
          style: TextStyle(color: colors.textPrimary),
          onChanged: _onCustomJSCodeChanged,
          minLines: 5,
          maxLines: 300,
          keyboardType: TextInputType.multiline,
        ),
      ],
    );
  }
}
