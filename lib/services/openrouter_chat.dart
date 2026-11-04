import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:open_vibrance/services/storage_service.dart';
import 'package:open_vibrance/transcription/types.dart';
import 'package:open_vibrance/utils/common.dart';

final Uri openRouterChatEndpoint = Uri.parse(
  'https://openrouter.ai/api/v1/chat/completions',
);

/// One keep-alive connection pool for every OpenRouter call. A new client per
/// request paid a fresh DNS + TCP + TLS handshake (~180 ms measured) twice per
/// Composite dictation: once for Gemini and once for the merger.
final http.Client _sharedClient = IOClient(
  HttpClient()..idleTimeout = const Duration(minutes: 2),
);

/// Gemini audio routing: standard endpoints only, AI Studio first. `flex`
/// (cheap queue, slow outliers) and `priority` (1.8x price, not faster in our
/// measurements) are excluded. Every Gemini model on OpenRouter has both tags.
const openRouterGeminiRouting = {
  'order': ['google-ai-studio', 'google-vertex/global'],
  'only': ['google-ai-studio', 'google-vertex/global'],
  'allow_fallbacks': true,
};

/// DeepSeek V4.1 Flash routing for the Composite merger: the two endpoints
/// with the lowest and steadiest latency in our measurements, then the usual
/// fallbacks minus Novita (ignores `reasoning.enabled: false`, 5-15 s).
const openRouterDeepSeekRouting = {
  'order': ['together', 'crusoe/fp8'],
  'ignore': ['novita'],
  'allow_fallbacks': true,
};

/// Opens the TLS connection to OpenRouter while the user is still speaking,
/// so the requests after the hotkey release reuse it. Never throws.
Future<void> warmUpOpenRouter(SecureStorageService storage) async {
  try {
    final apiKey = await readOpenRouterApiKey(storage);
    if (apiKey == null) return;
    await _sharedClient
        .get(
          Uri.parse('https://openrouter.ai/api/v1/key'),
          headers: {'Authorization': 'Bearer $apiKey'},
        )
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    dprint('[OpenRouter] warm-up failed: $e');
  }
}

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
  final httpClient = client ?? _sharedClient;
  final encoded = jsonEncode(body);
  Future<http.Response> send() => httpClient
      .post(
        openRouterChatEndpoint,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
          'X-OpenRouter-Title': 'Open Vibrance',
        },
        body: encoded,
      )
      .timeout(timeout);

  http.Response response;
  try {
    response = await send();
  } on http.ClientException catch (e) {
    // A pooled keep-alive socket the server closed while idle fails at once;
    // one retry on a fresh connection is enough.
    dprint('[OpenRouter] connection error, retrying once: $e');
    response = await send();
  }
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
