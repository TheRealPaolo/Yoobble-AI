// checkout_session_manager.dart
// ignore_for_file: avoid_print, use_build_context_synchronously, unnecessary_null_comparison, depend_on_referenced_packages
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../templates/accueill.dart';

class CheckoutSessionManager {
  final _apiKey = dotjsonenv.env['SECRET'] ?? "";
  static bool _isInitialized = false;

  Future<bool> hasUserUsedFreeTrial(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return false;

      final userData = userDoc.data() as Map<String, dynamic>;

      if (userData['trialValidated'] != true) return false;

      if (userData['trialStartDate'] != null) {
        final trialStartDate =
            (userData['trialStartDate'] as Timestamp).toDate();
        final now = DateTime.now();
        const trialDuration = Duration(days: 5);

        if (now.difference(trialStartDate) <= trialDuration) {
          return true;
        }

        if (userData['subscriptionStatus'] == 'trial') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'subscriptionStatus': 'expired',
            'trialEnded': true,
          });
        }
      }

      return userData['trialValidated'] == true;
    } catch (e) {
      print('Error checking free trial status: $e');
      return false;
    }
  }

  Future<bool> checkConfigExists() async {
    final doc = await FirebaseFirestore.instance
        .collection('config')
        .doc('subscription')
        .get();
    return doc.exists;
  }

  Future<Map<String, String>> createProducts() async {
    final standardProduct = await createProduct(
        'Standard Subscription', 'Standard access to all features');
    final proProduct =
        await createProduct('Pro Subscription', 'Pro access to all features');
    final businessProduct = await createProduct(
        'Business Subscription', 'Business access to all features');

    return {
      'standard': standardProduct,
      'pro': proProduct,
      'business': businessProduct,
    };
  }

  Future<String> createProduct(String name, String description) async {
    final url = Uri.parse('https://api.stripe.com/v1/products');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {
        'name': name,
        'description': description,
      },
    );

    if (response.statusCode == 200) {
      final product = jsonDecode(response.body);
      return product['id'];
    } else {
      throw Exception('Failed to create product');
    }
  }

  Future<Map<String, String>> createPrices(
      Map<String, String> productIds) async {
    final standardMonthlyPrice =
        await createPrice(productIds['standard']!, '900', 'month');
    final proMonthlyPrice =
        await createPrice(productIds['pro']!, '2900', 'month');
    final businessMonthlyPrice =
        await createPrice(productIds['business']!, '9900', 'month');
    final standardYearlyPrice =
        await createPrice(productIds['standard']!, '9000', 'year');
    final proYearlyPrice =
        await createPrice(productIds['pro']!, '29900', 'year');
    final businessYearlyPrice =
        await createPrice(productIds['business']!, '99900', 'year');

    return {
      'standardMonthly': standardMonthlyPrice,
      'proMonthly': proMonthlyPrice,
      'businessMonthly': businessMonthlyPrice,
      'standardYearly': standardYearlyPrice,
      'proYearly': proYearlyPrice,
      'businessYearly': businessYearlyPrice,
    };
  }

  Future<String> createPrice(
      String productId, String unitAmount, String interval) async {
    final url = Uri.parse('https://api.stripe.com/v1/prices');
    final body = {
      'unit_amount': unitAmount,
      'currency': 'usd',
      'recurring[interval]': interval,
      'product': productId,
    };

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );

    if (response.statusCode == 200) {
      final price = jsonDecode(response.body);
      return price['id'];
    } else {
      throw Exception('Failed to create price');
    }
  }

  Future<void> setupSubscriptions() async {
    final productIds = await createProducts();
    final priceIds = await createPrices(productIds);

    await FirebaseFirestore.instance
        .collection('config')
        .doc('subscription')
        .set({
      'standardMonthlyPriceId': priceIds['standardMonthly'],
      'proMonthlyPriceId': priceIds['proMonthly'],
      'businessMonthlyPriceId': priceIds['businessMonthly'],
      'standardYearlyPriceId': priceIds['standardYearly'],
      'proYearlyPriceId': priceIds['proYearly'],
      'businessYearlyPriceId': priceIds['businessYearly'],
    });
  }

  Future<String> createCustomer() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User not logged in');
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw Exception('User email is null or empty');
    }

    final url = Uri.parse('https://api.stripe.com/v1/customers');
    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: {'email': email},
    );

    if (response.statusCode == 200) {
      final customer = jsonDecode(response.body);
      return customer['id'];
    } else {
      throw Exception('Failed to create customer');
    }
  }

  Future<void> createCheckoutSession(
      BuildContext context, String subscriptionType, String periodType) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      if (!_isInitialized) {
        bool configExists = await checkConfigExists();
        if (!configExists) {
          await setupSubscriptions();
        }
        _isInitialized = true;
      }

      bool hasUsedTrial = await hasUserUsedFreeTrial(user.uid);
      final customerId = await createCustomer();

      DocumentSnapshot? doc;
      int maxRetries = 3;
      int currentRetry = 0;

      while (doc == null || !doc.exists && currentRetry < maxRetries) {
        doc = await FirebaseFirestore.instance
            .collection('config')
            .doc('subscription')
            .get();

        if (!doc.exists) {
          currentRetry++;
          if (currentRetry < maxRetries) {
            await Future.delayed(const Duration(seconds: 1));
          }
        }
      }

      if (!doc.exists) {
        throw Exception('Subscription configuration not found in Firestore');
      }

      String priceId;
      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

      if (periodType == 'monthly') {
        if (subscriptionType == 'standard') {
          priceId = data['standardMonthlyPriceId'];
        } else if (subscriptionType == 'pro') {
          priceId = data['proMonthlyPriceId'];
        } else if (subscriptionType == 'business') {
          priceId = data['businessMonthlyPriceId'];
        } else {
          throw Exception('Invalid subscription type');
        }
      } else if (periodType == 'yearly') {
        if (subscriptionType == 'standard') {
          priceId = data['standardYearlyPriceId'];
        } else if (subscriptionType == 'pro') {
          priceId = data['proYearlyPriceId'];
        } else if (subscriptionType == 'business') {
          priceId = data['businessYearlyPriceId'];
        } else {
          throw Exception('Invalid subscription type');
        }
      } else {
        throw Exception('Invalid period type');
      }

      if (priceId == null || priceId.isEmpty) {
        throw Exception('Price ID not found for selected subscription');
      }

      Map<String, String> body = {
        'payment_method_types[]': 'card',
        'line_items[0][price]': priceId,
        'line_items[0][quantity]': '1',
        'mode': 'subscription',
        'customer': customerId,
        'success_url': "https://x.com/Yoobble_?t=xSVFoJ5pRCZsaSFM0iB1Qg&s=09",
        'cancel_url': "https://x.com/Yoobble_?t=xSVFoJ5pRCZsaSFM0iB1Qg&s=09",
      };

      if (!hasUsedTrial) {
        body['subscription_data[trial_period_days]'] = '5';

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'trialStartDate': FieldValue.serverTimestamp(),
          'subscriptionStatus': 'trial',
          'trialValidated': false,
        }, SetOptions(merge: true));
      }

      final url = Uri.parse('https://api.stripe.com/v1/checkout/sessions');
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final sessionData = jsonDecode(response.body);
        await launchStripeCheckout(sessionData, context);
      } else {
        throw Exception(
            'Error creating payment session: ${response.statusCode}');
      }
    } catch (e) {
      print('Detailed exception during payment session creation:');
      print(e.toString());
      throw Exception('Error creating payment session: ${e.toString()}');
    }
  }

  Future<void> launchStripeCheckout(
      Map<String, dynamic> sessionData, BuildContext context) async {
    final String checkoutUrl = sessionData['url'];
    final String sessionId = sessionData['id'];

    if (checkoutUrl == null || checkoutUrl.isEmpty) {
      throw Exception('Invalid payment URL');
    }

    if (await canLaunchUrl(Uri.parse(checkoutUrl))) {
      await launchUrl(Uri.parse(checkoutUrl),
          mode: LaunchMode.externalApplication);

      bool paymentSuccessful = false;
      int attempts = 0;
      const maxAttempts = 60;

      while (!paymentSuccessful && attempts < maxAttempts) {
        await Future.delayed(const Duration(seconds: 5));
        paymentSuccessful = await checkPaymentStatus(sessionId);
        attempts++;
      }

      if (paymentSuccessful) {
        await handlePaymentSuccess(sessionId, context);
      } else {
        print('Payment not completed or confirmed after 5 minutes.');
      }
    } else {
      throw Exception('Cannot open $checkoutUrl');
    }
  }

  Future<bool> checkPaymentStatus(String sessionId) async {
    try {
      final url =
          Uri.parse('https://api.stripe.com/v1/checkout/sessions/$sessionId');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (response.statusCode == 200) {
        final sessionData = jsonDecode(response.body);
        return sessionData['payment_status'] == 'paid';
      } else {
        return false;
      }
    } catch (e) {
      print('Exception checking payment status: $e');
      return false;
    }
  }

  Future<void> handlePaymentSuccess(
      String sessionId, BuildContext context) async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final sessionUrl =
          Uri.parse('https://api.stripe.com/v1/checkout/sessions/$sessionId');
      final sessionResponse = await http.get(
        sessionUrl,
        headers: {'Authorization': 'Bearer $_apiKey'},
      );

      if (sessionResponse.statusCode == 200) {
        final sessionData = jsonDecode(sessionResponse.body);
        final customerId = sessionData['customer'];
        final subscriptionId = sessionData['subscription'];

        final subscriptionUrl = Uri.parse(
            'https://api.stripe.com/v1/subscriptions/$subscriptionId');
        final subscriptionResponse = await http.get(
          subscriptionUrl,
          headers: {'Authorization': 'Bearer $_apiKey'},
        );

        String planType = 'unknown';
        if (subscriptionResponse.statusCode == 200) {
          final subscriptionData = jsonDecode(subscriptionResponse.body);
          final plan = subscriptionData['plan'];
          final productName = plan['product'];

          final productUrl =
              Uri.parse('https://api.stripe.com/v1/products/$productName');
          final productResponse = await http.get(
            productUrl,
            headers: {'Authorization': 'Bearer $_apiKey'},
          );

          if (productResponse.statusCode == 200) {
            final productData = jsonDecode(productResponse.body);
            final name = productData['name'];

            if (name.toLowerCase().contains('standard')) {
              planType = 'standard';
            } else if (name.toLowerCase().contains('pro')) {
              planType = 'pro';
            } else if (name.toLowerCase().contains('business')) {
              planType = 'business';
            }
          }
        }

        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'customerId': customerId,
          'subscriptionId': subscriptionId,
          'subscriptionStatus': 'active',
          'planType': planType,
          'trialValidated': true,
          'hasUsedFreeTrial': true,
        }, SetOptions(merge: true));

        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const Accueil()),
        );
      } else {
        throw Exception(
            'Error retrieving session details: ${sessionResponse.statusCode}');
      }
    } catch (e) {
      print('Error processing successful payment: $e');
    }
  }

  static Future<void> checkTrialStatus(String userId) async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) return;

      final userData = userDoc.data() as Map<String, dynamic>;

      if (userData['subscriptionStatus'] == 'trial' &&
          userData['trialStartDate'] != null) {
        final trialStartDate =
            (userData['trialStartDate'] as Timestamp).toDate();
        final now = DateTime.now();
        const trialDuration = Duration(days: 5);

        if (now.difference(trialStartDate) > trialDuration) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .update({
            'subscriptionStatus': 'expired',
            'trialEnded': true,
          });
        }
      }
    } catch (e) {
      print('Error checking trial status: $e');
    }
  }
}
