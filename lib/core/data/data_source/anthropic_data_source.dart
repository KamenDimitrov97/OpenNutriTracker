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

/// One food item parsed out of a free-text meal description.
class ParsedFoodItem {
  final String name;
  final double grams;
  final double kcal;
  final double carbsG;
  final double fatG;
  final double proteinG;

  ParsedFoodItem({
    required this.name,
    required this.grams,
    required this.kcal,
    required this.carbsG,
    required this.fatG,
    required this.proteinG,
  });

  factory ParsedFoodItem.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) => (v is num) ? v.toDouble() : 0.0;
    return ParsedFoodItem(
      name: (json['name'] ?? '').toString(),
      grams: asDouble(json['grams']),
      kcal: asDouble(json['kcal']),
      carbsG: asDouble(json['carbs_g']),
      fatG: asDouble(json['fat_g']),
      proteinG: asDouble(json['protein_g']),
    );
  }
}

/// Talks to the Anthropic Messages API (https://api.anthropic.com/v1/messages).
class AnthropicDataSource {
  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _anthropicVersion = '2023-06-01';

  // "Sonnet 4.5 or newer" per the project brief. Bump to change models app-wide.
  static const _model = 'claude-sonnet-4-6';

  // The tool whose input schema IS our data shape. Forcing Claude to call it
  // guarantees we get structured items back instead of free-form text.
  static const Map<String, dynamic> _mealTool = {
    'name': 'log_food_items',
    'description':
        'Record the nutrition breakdown of the foods the user described, '
            'one entry per distinct food.',
    'input_schema': {
      'type': 'object',
      'properties': {
        'items': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'name': {'type': 'string', 'description': 'Short food name'},
              'grams': {
                'type': 'number',
                'description': 'Estimated portion weight in grams'
              },
              'kcal': {'type': 'number', 'description': 'Total calories'},
              'carbs_g': {'type': 'number'},
              'fat_g': {'type': 'number'},
              'protein_g': {'type': 'number'},
            },
            'required': [
              'name',
              'grams',
              'kcal',
              'carbs_g',
              'fat_g',
              'protein_g'
            ],
          },
        },
      },
      'required': ['items'],
    },
  };

  final SecureAppStorageProvider _secureStorage;
  final http.Client _client;

  AnthropicDataSource(this._secureStorage, this._client);

  /// Phase-2 connectivity check: returns Claude's reply to a "can you hear me?".
  Future<String> testConnection() async {
    final body = {
      'model': _model,
      'max_tokens': 256,
      'messages': [
        {
          'role': 'user',
          'content': 'This is a connection test from the NutriAssist mobile app. '
              'Can you hear me? Reply in one short, friendly sentence.',
        }
      ],
    };
    final decoded = await _post(body);
    final content = decoded['content'] as List<dynamic>?;
    final textBlock = content?.firstWhere(
      (b) => b is Map && b['type'] == 'text',
      orElse: () => null,
    );
    if (textBlock == null) {
      throw AnthropicException('No text in Claude\'s response.');
    }
    return (textBlock['text'] as String).trim();
  }

  /// Parses a free-text meal description into structured food items.
  Future<List<ParsedFoodItem>> parseMeal(String description) async {
    final body = {
      'model': _model,
      'max_tokens': 1024,
      'system':
          'You are a nutrition estimation assistant for a calorie tracker. The '
              'user describes what they ate in free text. Split it into individual '
              'food items and estimate the nutrition for the stated portion (or a '
              'typical serving if no quantity is given). Always respond by calling '
              'the log_food_items tool.',
      'tools': [_mealTool],
      'tool_choice': {'type': 'tool', 'name': 'log_food_items'},
      'messages': [
        {'role': 'user', 'content': description},
      ],
    };

    final decoded = await _post(body);
    final content = decoded['content'] as List<dynamic>?;
    if (content == null) {
      throw AnthropicException('Claude returned no content.');
    }

    // With a forced tool_choice, the reply contains a tool_use block whose
    // `input` matches our schema exactly.
    final toolUse = content.firstWhere(
      (b) =>
          b is Map && b['type'] == 'tool_use' && b['name'] == 'log_food_items',
      orElse: () => null,
    );
    if (toolUse == null) {
      throw AnthropicException('Claude did not return structured items.');
    }

    final input = toolUse['input'] as Map<String, dynamic>;
    final items = (input['items'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ParsedFoodItem.fromJson)
        .toList();
    if (items.isEmpty) {
      throw AnthropicException('No foods recognised in that description.');
    }
    return items;
  }

  /// Shared POST + error handling for both calls above.
  Future<Map<String, dynamic>> _post(Map<String, dynamic> body) async {
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
        body: jsonEncode(body),
      );
    } on Exception catch (e) {
      throw AnthropicException('Network error: $e');
    }

    if (response.statusCode != 200) {
      var detail = response.body;
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        detail = decoded['error']?['message']?.toString() ?? response.body;
      } catch (_) {/* keep raw body */}
      throw AnthropicException('HTTP ${response.statusCode}: $detail');
    }

    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
}