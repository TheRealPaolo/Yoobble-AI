// ignore_for_file: library_private_types_in_public_api, avoid_print, use_build_context_synchronously, depend_on_referenced_packages
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

class SubscriptionInfoPage extends StatefulWidget {
  const SubscriptionInfoPage({super.key});

  @override
  _SubscriptionInfoPageState createState() => _SubscriptionInfoPageState();
}

class _SubscriptionInfoPageState extends State<SubscriptionInfoPage> {
  bool isLoading = true;
  bool isSubscribed = false;
  Map<String, dynamic> userInfo = {};
  Map<String, dynamic> subscriptionInfo = {};
  String? customerId;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";

  @override
  void initState() {
    super.initState();
    fetchCustomerIdAndInfo();
    _startDailyCheck();
  }

  Timer? _dailyCheckTimer;

  void _startDailyCheck() {
    _dailyCheckTimer?.cancel();
    _dailyCheckTimer = Timer.periodic(
        const Duration(days: 1), (_) => checkSubscriptionStatus2());
  }

  @override
  void dispose() {
    _dailyCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> fetchCustomerIdAndInfo() async {
    await fetchCustomerId();
    if (customerId != null) {
      await fetchUserAndSubscriptionInfo();
    } else {
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erreur: CustomerId non trouvé')),
      );
    }
  }

  Future<void> fetchCustomerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      customerId = userData['customerId'] as String?;

      if (customerId == null) {
        print('CustomerId non trouvé pour cet utilisateur');
      }
    } else {
      print('Utilisateur non connecté');
    }
  }

  Future<void> fetchUserAndSubscriptionInfo() async {
    try {
      await fetchUserInfo();
      await checkSubscriptionStatus();
      setState(() {
        isLoading = false;
      });
    } catch (e) {
      print('Erreur: $e');
      setState(() {
        isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Erreur lors de la récupération des informations')),
      );
    }
  }

  Future<void> fetchUserInfo() async {
    final url = Uri.parse('https://api.stripe.com/v1/customers/$customerId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $stripeSecretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );

    if (response.statusCode == 200) {
      setState(() {
        userInfo = jsonDecode(response.body);
      });
    } else {
      throw Exception(
          'Erreur lors de la récupération des informations utilisateur');
    }
  }

  Future<void> checkSubscriptionStatus() async {
    final url = Uri.parse(
        'https://api.stripe.com/v1/customers/$customerId/subscriptions');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer $stripeSecretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );

    if (response.statusCode == 200) {
      final subscriptions = jsonDecode(response.body);
      final activeSubscriptions =
          subscriptions['data'].where((sub) => sub['status'] == 'active');

      if (activeSubscriptions.isNotEmpty) {
        final subscription = activeSubscriptions.first;
        final productId = subscription['plan']['product'];
        final productName = await fetchProductName(productId);
        final period = subscription['plan']['interval'];

        setState(() {
          isSubscribed = true;
          subscriptionInfo = {
            ...subscription,
            'productName': productName,
            'period': period,
          };
        });
      } else {
        final trialSubscriptions =
            subscriptions['data'].where((sub) => sub['status'] == 'trialing');

        if (trialSubscriptions.isNotEmpty) {
          final subscription = trialSubscriptions.first;
          final productId = subscription['plan']['product'];
          final productName = await fetchProductName(productId);
          final period = subscription['plan']['interval'];

          setState(() {
            isSubscribed = true;
            subscriptionInfo = {
              ...subscription,
              'productName': productName,
              'period': period,
            };
          });
        }
      }
    } else {
      throw Exception('Erreur lors de la vérification de l\'abonnement');
    }
  }

  Future<String> fetchProductName(String productId) async {
    final url = Uri.parse('https://api.stripe.com/v1/products/$productId');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $stripeSecretKey'},
    );

    if (response.statusCode == 200) {
      final product = jsonDecode(response.body);
      return product['name'] ?? 'Nom du produit inconnu';
    } else {
      return 'Nom du produit inconnu';
    }
  }

  Future<void> cancelSubscription() async {
    if (subscriptionInfo.isEmpty) return;

    final subscriptionId = subscriptionInfo['id'];
    final url =
        Uri.parse('https://api.stripe.com/v1/subscriptions/$subscriptionId');

    final response = await http.delete(
      url,
      headers: {
        'Authorization': 'Bearer $stripeSecretKey',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    );

    if (response.statusCode == 200) {
      final responseData = json.decode(response.body);
      final cancelAtPeriodEnd = responseData['cancel_at_period_end'];
      final currentPeriodEnd = DateTime.fromMillisecondsSinceEpoch(
          responseData['current_period_end'] * 1000);

      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'subscriptionStatus': 'cancelling',
          'subscriptionEndDate': currentPeriodEnd.toString(),
        });
      }

      setState(() {
        isSubscribed = true;
        subscriptionInfo = {
          ...subscriptionInfo,
          'cancel_at_period_end': cancelAtPeriodEnd,
          'current_period_end': currentPeriodEnd,
        };
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Subscription canceled. It will end at the end of the current period.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error canceling subscription')),
      );
    }
  }

  Future<void> checkSubscriptionStatus2() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();

    if (data != null) {
      final subscriptionStatus = data['subscriptionStatus'];
      final endDateString = data['subscriptionEndDate'];
      final subscriptionId = data['subscriptionId'];

      if (endDateString != null && subscriptionId != null) {
        final endDate = DateTime.parse(endDateString);

        if (DateTime.now().isAfter(endDate) ||
            subscriptionStatus == 'cancelling') {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .update({
            'subscriptionStatus': '',
            'subscriptionId': '',
            'subscriptionEndDate': null,
          });

          setState(() {
            isSubscribed = false;
            subscriptionInfo = {};
          });

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Votre abonnement est maintenant terminé.')),
          );
        } else if (subscriptionStatus == 'active') {
          setState(() {
            isSubscribed = true;
            subscriptionInfo = {
              ...subscriptionInfo,
              'status': 'active',
              'current_period_end': endDate.millisecondsSinceEpoch ~/ 1000,
            };
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Card(
        elevation: 5,
        color: Colors.white,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                  color: Colors.black,
                ))
              : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildUserInfoSection(),
                        const SizedBox(height: 30),
                        _buildSubscriptionInfoSection(),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildUserInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 5),
        CircleAvatar(
          radius: 10.w,
          backgroundImage:
              NetworkImage(FirebaseAuth.instance.currentUser!.photoURL!),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: _buildInfoTile(
                  'Name',
                  userInfo['name'] ??
                      FirebaseAuth.instance.currentUser!.displayName),
            ),
            Expanded(
              child: _buildInfoTile('Email', userInfo['email'] ?? 'N/A'),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildSubscriptionInfoSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Subscription',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 20),
        if (isSubscribed) ...[
          Row(
            children: [
              Expanded(
                child: _buildInfoTile(
                    'Status',
                    subscriptionInfo['status'] == 'trialing'
                        ? 'Trial'
                        : 'Active',
                    iconColor: subscriptionInfo['status'] == 'trialing'
                        ? Colors.orange
                        : Colors.green),
              ),
              Expanded(
                child: _buildInfoTile(
                    'Plan', subscriptionInfo['productName'] ?? 'N/A'),
              ),
            ],
          ),
          const SizedBox(
            height: 10,
          ),
          Row(
            children: [
              Expanded(
                child: _buildInfoTile(
                    'Period',
                    subscriptionInfo['period'] == 'month'
                        ? 'Monthly'
                        : subscriptionInfo['period'] == 'year'
                            ? 'Yearly'
                            : 'N/A'),
              ),
              if (subscriptionInfo['status'] == 'active')
                Expanded(
                  child: _buildInfoTile('Next payment',
                      _formatDate(subscriptionInfo['current_period_end'])),
                ),
            ],
          ),
          const SizedBox(height: 30),
          Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('Confirm Unsubscribe'),
                      content:
                          const Text('Are you sure you want to unsubscribe?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            cancelSubscription();
                          },
                          child: const Text('Unsubscribe'),
                        ),
                      ],
                    );
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding:
                    const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Unsubscribe',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ),
        ] else
          const Center(
            child: Text(
              'You are not currently subscribed',
              style:
                  TextStyle(color: Color.fromARGB(255, 8, 3, 1), fontSize: 18),
            ),
          ),
      ],
    );
  }

  Widget _buildInfoTile(String title, String value,
      {Color iconColor = Colors.blue}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.panorama_wide_angle_outlined,
                  color: iconColor, size: 20),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            ],
          ),
          const SizedBox(height: 5),
          Text(value,
              style: const TextStyle(color: Colors.black, fontSize: 16)),
        ],
      ),
    );
  }

  String _formatDate(dynamic timestamp) {
    if (timestamp == null) return 'N/A';

    int timestampInMilliseconds;
    if (timestamp is int) {
      timestampInMilliseconds = timestamp * 1000;
    } else if (timestamp is String) {
      timestampInMilliseconds = int.parse(timestamp) * 1000;
    } else {
      return 'Invalid date';
    }

    final date = DateTime.fromMillisecondsSinceEpoch(timestampInMilliseconds);
    return DateFormat('dd MMMM yyyy').format(date);
  }
}
