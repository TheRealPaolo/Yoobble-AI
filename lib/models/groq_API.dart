// ignore_for_file: file_names, depend_on_referenced_packages
import 'package:http/http.dart' as http;
import 'dart:convert';

class GroqApiService {
  final String apiKey;
  final String model;

  // URL de base de l'API Groq
  final String _baseUrl = 'https://api.groq.com/openai/v1/chat/completions';

  // Historique des messages
  final List<Map<String, String>> _messageHistory = [];

  GroqApiService({
    required this.apiKey,
    this.model = "llama-3.3-70b-versatile",
  });

  // Initialiser une session de chat
  void startChat() {
    _messageHistory.clear();
  }

  Future<String> generateContent(String prompt) async {
    try {
      // Ajouter le message de l'utilisateur à l'historique
      _messageHistory.add({"role": "user", "content": prompt});

      // Préparer la requête HTTP avec un client personnalisé pour gérer l'encodage
      final response = await http.post(
        Uri.parse(_baseUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': 'Bearer $apiKey',
          'Accept-Charset': 'utf-8',
        },
        body: jsonEncode({
          'model': model,
          'messages': _messageHistory,
          'temperature': 0.7,
          'max_tokens': 32000,
        }),
        encoding: Encoding.getByName('utf-8'), // Spécifier l'encodage UTF-8 ici
      );

      if (response.statusCode == 200) {
        // Décoder la réponse
        final jsonResponse = jsonDecode(utf8.decode(response.bodyBytes));
        final content =
            jsonResponse['choices'][0]['message']['content'] as String;

        // Ajouter la réponse à l'historique
        _messageHistory.add({"role": "assistant", "content": content});

        return content;
      } else {
        throw Exception('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception("Groq API error: $e");
    }
  }

  // Méthode pour effacer l'historique de la conversation
  void clearHistory() {
    _messageHistory.clear();
  }

  // Méthode pour obtenir l'historique de la conversation
  List<Map<String, String>> getMessageHistory() {
    return List.from(_messageHistory);
  }
}
