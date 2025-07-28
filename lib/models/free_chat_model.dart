// ignore_for_file: avoid_print
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatLimit {
  final String userId;
  final int chatCount;
  final DateTime date;

  ChatLimit({
    required this.userId,
    required this.chatCount,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'chatCount': chatCount,
      'date': date,
    };
  }

  factory ChatLimit.fromMap(Map<String, dynamic> map) {
    return ChatLimit(
      userId: map['userId'],
      chatCount: map['chatCount'],
      date: (map['date'] as Timestamp).toDate(),
    );
  }
}

class ChatLimitService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> canSendMessage(String userId) async {
    try {
      final today = DateTime.now();

      // Référence au document de l'utilisateur
      final userDoc = _firestore.collection('users').doc(userId);

      // Obtenir les données actuelles
      final userData = await userDoc.get();

      if (!userData.exists || userData.data()?['lastChatDate'] == null) {
        // Premier message ou pas de date précédente
        await userDoc.set({
          'chatCount': 1,
          'lastChatDate': today,
        }, SetOptions(merge: true));
        return true;
      }

      final lastChatDate =
          (userData.data()?['lastChatDate'] as Timestamp).toDate();
      final currentChatCount = userData.data()?['chatCount'] ?? 0;

      // Vérifier si c'est un nouveau jour
      if (lastChatDate.year != today.year ||
          lastChatDate.month != today.month ||
          lastChatDate.day != today.day) {
        // Réinitialiser pour le nouveau jour
        await userDoc.update({
          'chatCount': 1,
          'lastChatDate': today,
        });
        return true;
      }

      // Vérifier la limite pour aujourd'hui
      if (currentChatCount >= 5) {
        return false;
      }

      // Incrémenter le compteur
      await userDoc.update({
        'chatCount': FieldValue.increment(1),
        'lastChatDate': today,
      });

      return true;
    } catch (e) {
      print('Error checking chat limit: $e');
      return false;
    }
  }
}
