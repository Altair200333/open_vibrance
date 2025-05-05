import 'package:flutter/material.dart';
import 'package:open_vibrance/utils/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';

const double dotSize = 20;

class SettingsBox extends StatefulWidget {
  const SettingsBox({super.key, required this.expandedWindowSize});

  final Size expandedWindowSize;

  @override
  State<SettingsBox> createState() => _SettingsBoxState();
}

class _SettingsBoxState extends State<SettingsBox> {
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final key = await SecureStorageService().readValue(ApiKey.elevenLabs.key);
    if (key != null) {
      _apiKeyController.text = key;
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  void _onElevenLabsApiKeyChanged(String value) {
    SecureStorageService().saveValue(ApiKey.elevenLabs.key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: dotSize * 2,
      left: dotSize * 2.5,
      child: Container(
        width: widget.expandedWindowSize.width - dotSize * 3,
        height: widget.expandedWindowSize.height - dotSize * 3,
        decoration: BoxDecoration(
          color: Colors.grey.withAlpha(120),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white70, width: 1.5),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8)],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 16),
              Text('ElevenLabs API key', style: TextStyle(color: Colors.white)),
              SizedBox(height: 8),
              TextField(
                controller: _apiKeyController,
                decoration: InputDecoration(
                  hintText: 'Enter your API key',
                  hintStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.white70),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.white70),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8.0),
                    borderSide: BorderSide(color: Colors.blue, width: 2),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                ),
                style: TextStyle(color: Colors.white),
                onChanged: _onElevenLabsApiKeyChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
