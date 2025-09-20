import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/env.dart';

class AiChatService {
  final _log = Logger('AiChatService');

  final String apiKey;
  final String model;
  final Uri endpoint;

  AiChatService({
    String? apiKey,
    String? model,
    String? baseUrl,
  })  : apiKey = apiKey ?? Env.openAiApiKey,
        model = (() {
          if (model != null && model.isNotEmpty) return model;
          final dd = const String.fromEnvironment('OPENAI_MODEL');
          final env = Env.openAiModel; // may be empty if not set
          final effective = dd.isNotEmpty
              ? dd
              : (env.isNotEmpty ? env : 'gpt-4o-mini');
          return _normalizeModel(effective);
        })(),
        endpoint = Uri.parse((() {
          final dd = const String.fromEnvironment('OPENAI_BASE_URL');
          final env = Env.openAiBaseUrl;
          final base = (baseUrl != null && baseUrl.isNotEmpty)
              ? baseUrl
              : (dd.isNotEmpty ? dd : (env.isNotEmpty ? env : 'https://api.openai.com'));
          return base + '/v1/chat/completions';
        })());

  bool get hasApiKey => apiKey.isNotEmpty;

  Future<String?> send(List<AiMsg> history) async {
    if (!hasApiKey) {
      _log.warning('No OPENAI_API_KEY provided');
      return 'OpenAI key not set. Pass --dart-define=OPENAI_API_KEY=...';
    }
    // WARNING: Direct calls from web may fail due to CORS and expose the key.
    if (kIsWeb) {
      _log.warning('Running on web — direct OpenAI calls may fail due to CORS.');
    }

    final messages = [
      const {'role': 'system', 'content': 'You are a helpful assistant.'},
      for (final m in history)
        {
          'role': m.isUser ? 'user' : 'assistant',
          'content': m.text,
        }
    ];

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      // 'temperature': 0.2,
    });

    final resp = await http
        .post(
          endpoint,
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: body,
        )
        .timeout(const Duration(seconds: 25));

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      _log.warning('OpenAI error ${resp.statusCode}: ${resp.body}');
      return 'OpenAI error ${resp.statusCode}';
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final reportedModel = data['model']?.toString();
    final usage = (data['usage'] as Map?) ?? const {};
    final promptTokens = usage['prompt_tokens'];
    final completionTokens = usage['completion_tokens'];
    final totalTokens = usage['total_tokens'];
    _log.info('Model sources | dart-define: ' +
        (const String.fromEnvironment('OPENAI_MODEL').toString()) +
        ' | env: ' + Env.openAiModel + ' | effective: ' + model);
    _log.info('OpenAI model used: ' + (reportedModel ?? 'unknown') +
        ' | usage(prompt=' + (promptTokens?.toString() ?? '-') +
        ', completion=' + (completionTokens?.toString() ?? '-') +
        ', total=' + (totalTokens?.toString() ?? '-') + ')');
    final choices = (data['choices'] as List?) ?? const [];
    if (choices.isEmpty) return 'No response';
    final content = choices.first['message']?['content']?.toString();
    return content?.trim().isEmpty == false ? content : 'No response';
  }

  // Map friendly or legacy aliases to current model names.
  static String _normalizeModel(String m) {
    final s = m.trim().toLowerCase();
    switch (s) {
      case 'gpt5-mini':
      case 'gpt-5-mini':
      case 'gpt-5m':
      case 'gpt5m':
        return 'gpt-4o-mini';
      default:
        return m;
    }
  }
}

class AiMsg {
  final String text;
  final bool isUser;
  const AiMsg(this.text, this.isUser);
}
