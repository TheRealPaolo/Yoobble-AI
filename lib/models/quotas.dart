// ignore_for_file: avoid_print, depend_on_referenced_packages
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ApiQuotaManager {
  static final ApiQuotaManager _instance = ApiQuotaManager._internal();
  static const int dailyLimit =
      10; // Limite mensuelle pour les utilisateurs gratuits
  static const int _proDailyLimit =
      50; // Limite quotidienne pour les utilisateurs Pro
  static String stripeSecretKey =
      dotjsonenv.env['SECRET'] ?? ""; // Replace with your actual key

  factory ApiQuotaManager() {
    return _instance;
  }

  ApiQuotaManager._internal();

  // Initialize and verify user plan at app launch
  Future<void> initializeAndVerifyUserPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Full synchronization with Stripe to ensure data is up-to-date
      await synchronizeSubscriptionStatus(user.uid);
      print(
          "User plan verified and updated at app launch for user ${user.uid}");
    } catch (e) {
      print("Error initializing quota manager: $e");
    }
  }

  // Helper to get the current user's subscription plan and data
  Future<Map<String, dynamic>?> _getUserData(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      return userDoc.data();
    } catch (e) {
      print("Error fetching user data: $e");
      return null;
    }
  }

  // Méthodes de vérification d'abonnement avec Stripe
  Future<String?> _getCustomerId(String userId) async {
    DocumentSnapshot userData =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();

    final data = userData.data() as Map<String, dynamic>?;
    if (data != null && data.containsKey('customerId')) {
      return data['customerId'] as String?;
    }
    return null;
  }

  Future<Map<String, dynamic>> _fetchSubscriptionStatus(
      String customerId) async {
    final url = Uri.parse(
        'https://api.stripe.com/v1/customers/$customerId/subscriptions');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $stripeSecretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );

    Map<String, dynamic> result = {
      'planType': null,
      'isTrialing': false,
      'trialEndDate': null,
      'hasActiveSubscription': false
    };

    if (response.statusCode == 200) {
      final subscriptions = jsonDecode(response.body);
      final data = subscriptions['data'] as List;
      final activeSubscriptions = data.where(
          (sub) => sub['status'] == 'active' || sub['status'] == 'trialing');

      if (activeSubscriptions.isNotEmpty) {
        final subscription = activeSubscriptions.first;
        final productId = subscription['plan']['product'];

        // Vérifier si l'abonnement est en période d'essai
        if (subscription['status'] == 'trialing') {
          final trialEnd = subscription['trial_end'];
          if (trialEnd != null) {
            result['isTrialing'] = true;
            result['trialEndDate'] =
                DateTime.fromMillisecondsSinceEpoch(trialEnd * 1000);
          }
        }

        result['hasActiveSubscription'] = true;
        result['planType'] = await _fetchProductName(productId);
      }
    } else {
      print(
          'Error fetching subscription from Stripe: ${response.statusCode} - ${response.body}');
    }
    return result;
  }

  Future<String> _fetchProductName(String productId) async {
    final url = Uri.parse('https://api.stripe.com/v1/products/$productId');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $stripeSecretKey'},
    );

    if (response.statusCode == 200) {
      final product = jsonDecode(response.body);
      final productName = product['name'];

      if (productName.contains('standard')) {
        return 'standard';
      } else if (productName.contains('Pro')) {
        return 'pro';
      } else if (productName.contains('Business')) {
        return 'business';
      } else {
        return 'Unknown';
      }
    } else {
      print(
          'Error fetching product name from Stripe: ${response.statusCode} - ${response.body}');
      return 'Unknown';
    }
  }

  // Synchronize Firestore data with actual Stripe subscription status
  Future<void> synchronizeSubscriptionStatus(String userId) async {
    try {
      // Fetch current user data to detect plan changes
      final currentUserData = await _getUserData(userId);
      final currentPlanType = currentUserData?['planType'] as String? ?? '';

      final customerId = await _getCustomerId(userId);
      if (customerId == null || customerId.isEmpty) {
        // User has no customerId, reset to free plan
        await _resetToFreePlan(userId);
        return;
      }

      // Get current status from Stripe
      final stripeStatus = await _fetchSubscriptionStatus(customerId);
      final newPlanType = stripeStatus['planType'] ?? '';

      // Check if plan type has changed
      final hasPlanChanged = currentPlanType != newPlanType;

      // Update user data in Firestore
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'planType': newPlanType,
        'isTrialing': stripeStatus['isTrialing'] ?? false,
        'trialEndDate': stripeStatus['trialEndDate'] != null
            ? Timestamp.fromDate(stripeStatus['trialEndDate'])
            : null,
        'hasActiveSubscription': stripeStatus['hasActiveSubscription'] ?? false,
        'lastSubscriptionCheck': FieldValue.serverTimestamp(),
      });

      // If plan has changed, reset today's quota usage to zero
      if (hasPlanChanged) {
        await _resetTodayQuota(userId);
        print(
            "User $userId changed from plan '$currentPlanType' to '$newPlanType', today's usage reset to zero.");
      }

      // If trial ended and no active subscription, reset to free plan
      if (!stripeStatus['hasActiveSubscription'] &&
          (!stripeStatus['isTrialing'] ||
              (stripeStatus['trialEndDate'] != null &&
                  stripeStatus['trialEndDate'].isBefore(DateTime.now())))) {
        await _resetToFreePlan(userId);
      }
    } catch (e) {
      print("Error synchronizing subscription status: $e");
    }
  }

  // Reset user to free plan when trial ended without payment
  Future<void> _resetToFreePlan(String userId) async {
    await FirebaseFirestore.instance.collection('users').doc(userId).update({
      'planType': '',
      'isTrialing': false,
      'trialEndDate': null,
      'hasActiveSubscription': false,
    });
    print("User $userId reset to free plan");
  }

  // Reset today's quota usage to zero when plan changes
  Future<void> _resetTodayQuota(String userId) async {
    try {
      // Pour les utilisateurs Pro, réinitialise le quota quotidien
      final userData = await _getUserData(userId);
      final subscriptionPlan = userData?['planType'] as String?;

      if (subscriptionPlan?.toLowerCase() == 'pro') {
        final today = DateTime.now().toIso8601String().split('T')[0];
        await FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(userId)
            .collection('dailyUsage')
            .doc(today)
            .set({'count': 0, 'date': FieldValue.serverTimestamp()});
      } else {
        // Pour les utilisateurs gratuits, réinitialise le quota mensuel
        final currentMonth = _getCurrentMonthKey();
        await FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(userId)
            .collection('monthlyUsage')
            .doc(currentMonth)
            .set({'count': 0, 'date': FieldValue.serverTimestamp()});
      }

      print("Reset quota usage to zero for user $userId due to plan change");
    } catch (e) {
      print("Error resetting quota: $e");
    }
  }

  // Helper to get the current month in format YYYY-MM
  String _getCurrentMonthKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  // Helper to check if trial subscription is still valid
  Future<bool> _isTrialStillValid(String userId) async {
    try {
      // First check local data
      final userData = await _getUserData(userId);
      if (userData == null) return false;

      // Check if user has customerId for Stripe
      final customerId = userData['customerId'] as String?;
      if (customerId == null || customerId.isEmpty) return false;

      // Check if we need to refresh subscription data (e.g., after trial end date)
      final isTrialing = userData['isTrialing'] as bool?;
      final trialEndDate = userData['trialEndDate'] as Timestamp?;
      final lastCheck = userData['lastSubscriptionCheck'] as Timestamp?;

      // If we have local data showing trial already ended, no need to check Stripe
      if (isTrialing == false || trialEndDate == null) {
        return false;
      }

      // If trial end date has passed or we haven't checked in more than a day, verify with Stripe
      final shouldCheckStripe =
          trialEndDate.toDate().isBefore(DateTime.now()) ||
              lastCheck == null ||
              DateTime.now().difference(lastCheck.toDate()).inHours > 24;

      if (shouldCheckStripe) {
        await synchronizeSubscriptionStatus(userId);

        // Get fresh data after synchronization
        final freshUserData = await _getUserData(userId);
        if (freshUserData == null) return false;

        final freshIsTrialing = freshUserData['isTrialing'] as bool?;
        final freshTrialEndDate = freshUserData['trialEndDate'] as Timestamp?;

        if (freshIsTrialing == true && freshTrialEndDate != null) {
          return freshTrialEndDate.toDate().isAfter(DateTime.now());
        }
        return false;
      }

      // Otherwise, trust our cached data
      return trialEndDate.toDate().isAfter(DateTime.now());
    } catch (e) {
      print("Error checking trial validity: $e");
      return false;
    }
  }

  // Helper to get usage count based on subscription type
  Future<int> _getCurrentUsageCount(
      String userId, String? subscriptionPlan) async {
    try {
      // Pour les utilisateurs Pro, compte l'utilisation quotidienne
      if (subscriptionPlan?.toLowerCase() == 'pro') {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final quotaDoc = await FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(userId)
            .collection('dailyUsage')
            .doc(today)
            .get();

        if (!quotaDoc.exists) {
          return 0;
        }
        return quotaDoc.data()?['count'] ?? 0;
      } else {
        // Pour les utilisateurs gratuits, compte l'utilisation mensuelle
        final currentMonth = _getCurrentMonthKey();
        final quotaDoc = await FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(userId)
            .collection('monthlyUsage')
            .doc(currentMonth)
            .get();

        if (!quotaDoc.exists) {
          return 0;
        }
        return quotaDoc.data()?['count'] ?? 0;
      }
    } catch (e) {
      print("Error fetching usage count: $e");
      return 0;
    }
  }

  // Determines the applicable daily limit based on the plan
  Future<int> _getLimitForPlan(String? subscriptionPlan, String userId) async {
    // Vérifier si l'utilisateur a un abonnement actif ou est en essai valide
    if (subscriptionPlan == null || subscriptionPlan.isEmpty) {
      // Vérifier si l'utilisateur est en période d'essai valide
      final isTrialValid = await _isTrialStillValid(userId);
      if (isTrialValid) {
        // Si en essai valide, donner accès comme un utilisateur Standard
        return -1; // Unlimited access during trial
      }
      return dailyLimit; // Utilisateur sans plan = plan gratuit (10 par mois)
    }

    // Cas normal - vérification du type d'abonnement
    if (subscriptionPlan.toLowerCase() == 'pro') {
      return _proDailyLimit;
    }

    // Pour Standard et Business, accès illimité
    if (subscriptionPlan.toLowerCase() == 'standard' ||
        subscriptionPlan.toLowerCase() == 'business') {
      return -1; // Indicate unlimited
    }

    // Fallback pour tout autre plan inattendu
    return dailyLimit;
  }

  // Vérifie si l'utilisateur peut faire une requête API
  Future<bool> canMakeApiRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    // Périodiquement vérifier le statut d'abonnement avec Stripe
    await _periodicSubscriptionCheck(user.uid);

    final userData = await _getUserData(user.uid);
    final subscriptionPlan = userData?['planType'] as String?;

    // Obtenir la limite applicable pour ce plan, y compris vérification de l'essai
    final currentLimit = await _getLimitForPlan(subscriptionPlan, user.uid);

    // Accès illimité
    if (currentLimit == -1) {
      return true;
    }

    // Vérification du quota en fonction du type d'abonnement
    final usageCount = await _getCurrentUsageCount(user.uid, subscriptionPlan);
    return usageCount < currentLimit;
  }

  // Periodic subscription check with Stripe
  Future<void> _periodicSubscriptionCheck(String userId) async {
    try {
      final userData = await _getUserData(userId);
      if (userData == null) return;

      final lastCheck = userData['lastSubscriptionCheck'] as Timestamp?;
      final isTrialing = userData['isTrialing'] as bool?;
      final trialEndDate = userData['trialEndDate'] as Timestamp?;

      // Check with Stripe if:
      // 1. We haven't checked in 24 hours, or
      // 2. User is trialing and trial end date is approaching (within 12 hours), or
      // 3. User was trialing and the end date has passed
      final shouldCheck = lastCheck == null ||
          DateTime.now().difference(lastCheck.toDate()).inHours > 24 ||
          (isTrialing == true &&
              trialEndDate != null &&
              DateTime.now().difference(trialEndDate.toDate()).inHours.abs() <
                  12) ||
          (isTrialing == true &&
              trialEndDate != null &&
              trialEndDate.toDate().isBefore(DateTime.now()));

      if (shouldCheck) {
        await synchronizeSubscriptionStatus(userId);
      }
    } catch (e) {
      print("Error during periodic subscription check: $e");
    }
  }

  // Récupère le nombre de requêtes restantes pour aujourd'hui
  Future<int> getRemainingQuota() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 0;

    // Périodiquement vérifier le statut d'abonnement avec Stripe
    await _periodicSubscriptionCheck(user.uid);

    final userData = await _getUserData(user.uid);
    final subscriptionPlan = userData?['planType'] as String?;

    // Obtenir la limite applicable, y compris vérification de l'essai
    final currentLimit = await _getLimitForPlan(subscriptionPlan, user.uid);

    // Accès illimité
    if (currentLimit == -1) {
      return -1; // -1 indique un quota illimité
    }

    // Calcul des requêtes restantes en fonction du type d'abonnement
    final usageCount = await _getCurrentUsageCount(user.uid, subscriptionPlan);
    final remaining = currentLimit - usageCount;

    return remaining > 0
        ? remaining
        : 0; // Ensure remaining quota is not negative
  }

  // Récupère la limite quotidienne applicable à l'utilisateur actuel
  Future<int> getCurrentDailyLimit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return dailyLimit; // Default to free limit if no user

    // Périodiquement vérifier le statut d'abonnement avec Stripe
    await _periodicSubscriptionCheck(user.uid);

    final userData = await _getUserData(user.uid);
    final subscriptionPlan = userData?['planType'] as String?;

    return await _getLimitForPlan(subscriptionPlan, user.uid);
  }

  // Enregistre une utilisation de l'API
  Future<void> recordApiUsage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Périodiquement vérifier le statut d'abonnement avec Stripe
    await _periodicSubscriptionCheck(user.uid);

    final userData = await _getUserData(user.uid);
    final subscriptionPlan = userData?['planType'] as String?;

    // Vérifier si l'utilisateur a un accès illimité
    final currentLimit = await _getLimitForPlan(subscriptionPlan, user.uid);

    // Ne pas enregistrer l'utilisation pour les utilisateurs à accès illimité
    if (currentLimit == -1) {
      return;
    }

    // Utiliser une transaction pour garantir l'atomicité
    try {
      if (subscriptionPlan?.toLowerCase() == 'pro') {
        // Enregistrer l'utilisation quotidienne pour les utilisateurs Pro
        final today = DateTime.now().toIso8601String().split('T')[0];
        final quotaRef = FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(user.uid)
            .collection('dailyUsage')
            .doc(today);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(quotaRef);

          if (!snapshot.exists) {
            transaction.set(
                quotaRef, {'count': 1, 'date': FieldValue.serverTimestamp()});
          } else {
            final currentCount = snapshot.data()?['count'] ?? 0;
            transaction.update(quotaRef, {'count': currentCount + 1});
          }
        });
      } else {
        // Enregistrer l'utilisation mensuelle pour les utilisateurs gratuits
        final currentMonth = _getCurrentMonthKey();
        final quotaRef = FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(user.uid)
            .collection('monthlyUsage')
            .doc(currentMonth);

        await FirebaseFirestore.instance.runTransaction((transaction) async {
          final snapshot = await transaction.get(quotaRef);

          if (!snapshot.exists) {
            transaction.set(
                quotaRef, {'count': 1, 'date': FieldValue.serverTimestamp()});
          } else {
            final currentCount = snapshot.data()?['count'] ?? 0;
            transaction.update(quotaRef, {'count': currentCount + 1});
          }
        });
      }

      // Consider moving cleanup to a scheduled function for efficiency,
      // but calling it here ensures it runs periodically with user activity.
      _cleanOldQuotaData();
    } catch (e) {
      print("Error recording API usage: $e");
      // Handle error appropriately, maybe retry or log centrally
    }
  }

  // Nettoyer les anciennes données de quota
  Future<void> _cleanOldQuotaData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final userData = await _getUserData(user.uid);
      final subscriptionPlan = userData?['planType'] as String?;

      if (subscriptionPlan?.toLowerCase() == 'pro') {
        // Pour les utilisateurs Pro, nettoyer les données quotidiennes anciennes
        // Conserver uniquement les données d'hier et d'aujourd'hui
        final yesterdayStart = DateTime(
                DateTime.now().year, DateTime.now().month, DateTime.now().day)
            .subtract(const Duration(days: 1));

        final oldDailyQuotasQuery = FirebaseFirestore.instance
            .collection('apiQuotas')
            .doc(user.uid)
            .collection('dailyUsage')
            .where('date', isLessThan: Timestamp.fromDate(yesterdayStart));

        final oldDailyQuotasSnapshot = await oldDailyQuotasQuery.get();

        if (oldDailyQuotasSnapshot.docs.isNotEmpty) {
          final batch = FirebaseFirestore.instance.batch();
          for (var doc in oldDailyQuotasSnapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
          print(
              "Cleaned ${oldDailyQuotasSnapshot.docs.length} old daily quota documents.");
        }
      }

      // Pour tous les utilisateurs, nettoyer les données mensuelles anciennes
      // Conserver uniquement les données des 3 derniers mois
      final threeMonthsAgo = DateTime.now().subtract(const Duration(days: 90));
      final cutoffMonthKey =
          '${threeMonthsAgo.year}-${threeMonthsAgo.month.toString().padLeft(2, '0')}';

      final oldMonthlyQuotasQuery = FirebaseFirestore.instance
          .collection('apiQuotas')
          .doc(user.uid)
          .collection('monthlyUsage')
          .where(FieldPath.documentId, isLessThan: cutoffMonthKey);

      final oldMonthlyQuotasSnapshot = await oldMonthlyQuotasQuery.get();

      if (oldMonthlyQuotasSnapshot.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (var doc in oldMonthlyQuotasSnapshot.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
        print(
            "Cleaned ${oldMonthlyQuotasSnapshot.docs.length} old monthly quota documents.");
      }
    } catch (e) {
      print("Error cleaning old quota data: $e");
    }
  }

  // Constantes pour les limites quotidiennes (getters)
  static int get freeDailyLimit => dailyLimit;
  static int get proDailyLimit => _proDailyLimit;
}
