// ignore_for_file: use_build_context_synchronously, avoid_print, depend_on_referenced_packages
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../stripe/paywall.dart';
import '../templates/accueill.dart';

class Paypass extends StatefulWidget {
  const Paypass({super.key});

  @override
  State<Paypass> createState() => _PaypassState();
}

class _PaypassState extends State<Paypass> {
  bool isSubscribed = false;
  bool isAdmin = false;
  final _apiKey = dotjsonenv.env['SECRET'] ?? "";

  @override
  void initState() {
    super.initState();
    checkStatusAndRedirect();
  }

  Future<void> checkStatusAndRedirect() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      redirectToPaywall();
      return;
    }

    final adminUid = dotjsonenv.env['ADMIN'];
    isAdmin = currentUser.uid == adminUid;

    if (isAdmin) {
      redirectToAccueil();
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    final customerId = userDoc.data()?['customerId'];
    if (customerId == null) {
      redirectToPaywall();
      return;
    }

    final isSubscribedResult = await checkSubscriptionStatus(customerId);
    if (isSubscribedResult) {
      redirectToAccueil();
    } else {
      redirectToPaywall();
    }
  }

  Future<bool> checkSubscriptionStatus(String customerId) async {
    try {
      final subscriptionsUrl = Uri.parse(
          'https://api.stripe.com/v1/subscriptions?customer=$customerId&limit=1');
      final subscriptionsResponse = await http.get(
        subscriptionsUrl,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (subscriptionsResponse.statusCode == 200) {
        final subscriptionsData = jsonDecode(subscriptionsResponse.body);
        final subscriptions = subscriptionsData['data'];

        if (subscriptions != null && subscriptions.isNotEmpty) {
          final subscription = subscriptions[0];
          final subscriptionStatus = subscription['status'];
          final currentPeriodEnd = subscription['current_period_end'];
          final trialEnd = subscription['trial_end'];

          final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

          return (subscriptionStatus == 'trialing' && trialEnd > now) ||
              (subscriptionStatus == 'active' && currentPeriodEnd > now);
        }
      }
    } catch (e) {
      print('Error checking subscription status: $e');
    }
    return false;
  }

  void redirectToAccueil() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const Accueil()),
      );
    });
  }

  void redirectToPaywall() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
            builder: (context) => const SubscriptionBottomSheet()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: LoadingAnimationWidget.twistingDots(
          leftDotColor: const Color.fromARGB(255, 4, 4, 9),
          rightDotColor: const Color.fromARGB(255, 55, 70, 234),
          size: 30,
        ),
      ),
    );
  }
}
