import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';

/// Thrown for any Anthropic call failure, with a message safe to show the user.
class AnthropicException implements Exception {
  final String message;
  AnthropicException(this.message);

  @override
  String toString() => message;
}

/// Talks to the Anthropic Messages API (https://api.anthropic.com/v1/messages).
/// Phase 2 only needs a connection test; Phase 3 will add structured meal parsing.
class AnthropicDataSource {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';

  // The API requires this header; it's a fixed version date, not your key.
  static const _anthropicVersion = '2023-06-01';

  // "Sonnet 4.5 or newer" per the project brief — this is the latest Sonnet.
  // Bump this one constant to change models app-wide.
  static const _model = 'claude-sonnet-4-6';

  final SecureAppStorageProvider _secureStorage;
  final http.Client _client;

  AnthropicDataSource(this._secureStorage, this._client);

  /// Sends a one-line "are you there?" and returns Claude's reply text.
  /// Throws [AnthropicException] (with a readable message) on any failure.
  Future<String> testConnection() async {
    final apiKey = await _secureStorage.getAnthropicApiKey();
    if (apiKey == null || apiKey.isEmpty) {
      throw AnthropicException('No API key saved yet.');
    }

    final http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_endpoint),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': _anthropicVersion,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 256,
          'messages': [
            {
              'role': 'user',
              'content': 'This is a connection test from the NutriAssist mobile '
                  'app. Can you hear me? Reply in one short, friendly sentence.',
            }
          ],
        }),
      );
    } on Exception catch (e) {
      // No network, DNS failure, TLS error, etc.
      throw AnthropicException('Network error: $e');
    }

    if (response.statusCode != 200) {
      // Anthropic errors look like {"error": {"type": ..., "message": ...}}.
      var detail = response.body;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        detail = decoded['error']?['message']?.toString() ?? response.body;
      } catch (_) {/* keep raw body */}
      throw AnthropicException('HTTP ${response.statusCode}: $detail');
    }

    final decoded =
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final content = decoded['content'] as List<dynamic>?;
    if (content == null || content.isEmpty) {
      throw AnthropicException('Claude returned an empty response.');
    }

    final textBlock = content.firstWhere(
      (block) => block is Map && block['type'] == 'text',
      orElse: () => null,
    );
    if (textBlock == null) {
      throw AnthropicException('No text block in Claude\'s response.');
    }
    return (textBlock['text'] as String).trim();
  }
}