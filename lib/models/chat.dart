class Message {
  final String content;
  final bool isUser;
  final String? imageBase64;
  final DateTime timestamp;
  final bool isGeneratedResponse;

  Message({
    required this.content,
    required this.isUser,
    this.imageBase64,
    required this.timestamp,
    this.isGeneratedResponse = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'isUser': isUser,
      'imageBase64': imageBase64,
      'timestamp': timestamp.toIso8601String(),
      'isGeneratedResponse': isGeneratedResponse,
    };
  }

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      content: json['content'],
      isUser: json['isUser'],
      imageBase64: json['imageBase64'],
      timestamp: DateTime.parse(json['timestamp']),
      isGeneratedResponse: json['isGeneratedResponse'] ?? false,
    );
  }
}
