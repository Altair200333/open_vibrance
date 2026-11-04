import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';

final Uri openRouterChatEndpoint = Uri.parse(
  'https://openrouter.ai/api/v1/chat/completions',
);

/// The Google provider and the Composite merger both talk to OpenRouter.
/// The user may have typed the key into either field, so each one prefers its
/// own storage slot and falls back to the other — the key is entered once.
Future<String?> readOpenRouterApiKey(
  SecureStorageService storage, {
  StorageKey preferred = StorageKey.openRouterApiKey,
}) async {
  final fallback =
      preferred == StorageKey.googleApiKey
          ? StorageKey.openRouterApiKey
          : StorageKey.googleApiKey;
  for (final key in [preferred, fallback]) {
    final value = (await storage.readValue(key.key))?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return null;
}

/// Every OpenRouter key field (Google, Composite, ElevenLabs filtering) writes
/// both slots, so a stale value in one can never shadow a fresh edit.
Future<void> saveOpenRouterApiKey(
  SecureStorageService storage,
  String value,
) async {
  await storage.saveValue(StorageKey.openRouterApiKey.key, value);
  await storage.saveValue(StorageKey.googleApiKey.key, value);
}

/// Sends one chat completion request and returns the trimmed message text.
/// Throws on transport errors, non-2xx status, or a malformed response.
Future<String> postOpenRouterChat({
  required String apiKey,
  required Map<String, dynamic> body,
  required Duration timeout,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .post(
          openRouterChatEndpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-OpenRouter-Title': 'Open Vibrance',
          },
          body: jsonEncode(body),
        )
        .timeout(timeout);
    final responseBody = utf8.decode(response.bodyBytes);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final snippet =
          responseBody.length > 300
              ? '${responseBody.substring(0, 300)}…'
              : responseBody;
      throw Exception(
        'OpenRouter ${body['model']} failed '
        '(HTTP ${response.statusCode}): $snippet',
      );
    }
    return _parseContent(responseBody);
  } finally {
    if (client == null) httpClient.close();
  }
}

String _parseContent(String responseBody) {
  final response = jsonDecode(responseBody);
  if (response is! Map<String, dynamic>) {
    throw const FormatException('OpenRouter response is not an object');
  }
  final choices = response['choices'];
  if (choices is! List || choices.isEmpty) {
    throw const FormatException('OpenRouter response has no choices');
  }
  final message = (choices.first as Map<String, dynamic>?)?['message'];
  if (message is! Map<String, dynamic>) {
    throw const FormatException('OpenRouter response has no message');
  }
  final content = message['content'];
  if (content is String) return content.trim();
  if (content is List) {
    return content
        .whereType<Map<String, dynamic>>()
        .map((part) => part['text'])
        .whereType<String>()
        .join()
        .trim();
  }
  throw const FormatException('OpenRouter response has no content');
}
