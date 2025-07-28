// ignore_for_file: deprecated_member_use, use_build_context_synchronously, avoid_print
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:sizer/sizer.dart';
import '../templates/login.dart';
import 'stripe_sub.dart';

class SubscriptionBottomSheet extends StatefulWidget {
  const SubscriptionBottomSheet({super.key});

  @override
  State<SubscriptionBottomSheet> createState() =>
      SubscriptionBottomSheetState();
}

class SubscriptionBottomSheetState extends State<SubscriptionBottomSheet> {
  bool isYearlySelected = false;
  bool isLoading = false; // Variable to track loading state

  List<String> freePlan = [
    '10 requests per month  ⏱️',
    'One-Shot Blog Post Creator 📝',
    'Email Generator 📧',
    'Social Media Post Generator 📱',
    'Press Article Generator 📰',
    'Ads Generator for Marketing 📢',
  ];

  List<String> proFeatures = [
    '50 RPD/1500 per months⏱️',
    'One-Shot Blog Post Creator 📝',
    'Email Generator 📧',
    'Social Media Post Generator 📱',
    'Press Article Generator 📰',
    'Ads Generator for Marketing 📢',
  ];

  List<String> businessFeatures = [
    'All Pro Features ✓',
    'Unlimited requests per day ♾️',
    'Free Content AI Agent 🤖',
    'Citation Tool 📚',
    'Advanced Translation Features 🌐',
    'Personalized Chat Assistant 💬',
    'Priority Support ⭐',
  ];

  @override
  Widget build(BuildContext context) {
    final bool isDesktop = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: Colors.white,
      body: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
    );
  }

//////////////////MOBILE//////////////////////////////////////////////////////////////////////////////////////////////
  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                "Choose Your Yoobble Plan",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(
                "Unlock premium features to boost your content creation",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            _buildToggleSwitch(),
            const SizedBox(height: 16),
            _buildFreePlanCard(), // Free plan card (vertical on mobile)
            const SizedBox(height: 16),
            _buildPlanCards(),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

///////////////////////////DESKTOP/////////////////////////////////////////////////////////////////////////////
  Widget _buildDesktopLayout() {
    return SingleChildScrollView(
      child: Center(
        child: Container(
          width: 1000,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              const Text(
                "Choose Your Yoobble Plan",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "Unlock premium features to boost your content creation",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              _buildToggleSwitch(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  _buildFreePlanCard(), // Free plan card (in row on desktop)
                  ..._buildPlanCardsList(), // Other plan cards
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPlanCardsList() {
    // Helper function to create a list of plan cards
    return isYearlySelected
        ? [
            _buildPlanCard(subscriptionType: 'pro', periodType: 'yearly'),
            _buildPlanCard(subscriptionType: 'business', periodType: 'yearly'),
          ]
        : [
            _buildPlanCard(subscriptionType: 'pro', periodType: 'monthly'),
            _buildPlanCard(subscriptionType: 'business', periodType: 'monthly'),
          ];
  }

  Widget _buildToggleSwitch() {
    // Ajuster le padding en fonction de la taille de l'écran
    double screenWidth = MediaQuery.of(context).size.width;
    double horizontalPadding;

    if (screenWidth > 600) {
      // Desktop
      horizontalPadding = 300.0;
    } else if (screenWidth > 400) {
      // Medium mobile
      horizontalPadding = 80.0;
    } else {
      // Small mobile
      horizontalPadding = 32.0;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Card(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Container(
          height: 4.h,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      isYearlySelected = false;
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color:
                          !isYearlySelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'Monthly',
                        style: TextStyle(
                          color:
                              !isYearlySelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      isYearlySelected = true;
                    });
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    decoration: BoxDecoration(
                      color:
                          isYearlySelected ? Colors.black : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        'Yearly',
                        style: TextStyle(
                          color:
                              isYearlySelected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCards() {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.center,
      children: _buildPlanCardsList(),
    );
  }

  Widget _buildFreePlanCard() {
    return Container(
      width: MediaQuery.of(context).size.width > 600 ? 300 : double.infinity,
      margin: EdgeInsets.symmetric(
        vertical: 8,
        horizontal: MediaQuery.of(context).size.width > 600 ? 0 : 12,
      ),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'CURRENT PLAN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Free Plan',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            '\$0',
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Forever free',
            style: TextStyle(color: Colors.black54, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const Text(
            'Features:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ...freePlan.map((feature) => _buildFeatureItem(feature)),
        ],
      ),
    );
  }

  Widget _buildPlanCard(
      {required String subscriptionType, required String periodType}) {
    String title;
    String price;
    String interval;
    String trialPeriod;
    List<String> features;
    Color cardAccentColor;
    bool isBestValue = false;

    if (periodType == 'monthly') {
      switch (subscriptionType) {
        case 'pro':
          title = 'Pro Plan';
          price = '\$29';
          interval = '/month';
          trialPeriod = '5-day free trial';
          features = proFeatures;
          cardAccentColor = Colors.blue.shade50;
          break;
        case 'business':
          title = 'Pro+ Plan';
          price = '\$99';
          interval = '/month';
          trialPeriod = '5-day free trial';
          features = businessFeatures;
          cardAccentColor = Colors.purple.shade50;
          isBestValue = true;
          break;
        default:
          throw ArgumentError('Invalid subscription type');
      }
    } else {
      switch (subscriptionType) {
        case 'pro':
          title = 'Pro Plan';
          price = '\$299';
          interval = '/year';
          trialPeriod = '7-day free trial';
          features = proFeatures;
          cardAccentColor = Colors.blue.shade50;
          break;
        case 'business':
          title = 'Pro+';
          price = '\$999';
          interval = '/year';
          trialPeriod = '7-day free trial';
          features = businessFeatures;
          cardAccentColor = Colors.purple.shade50;
          isBestValue = true;
          break;
        default:
          throw ArgumentError('Invalid subscription type');
      }
    }

    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        return Container(
          width:
              MediaQuery.of(context).size.width > 600 ? 300 : double.infinity,
          margin: EdgeInsets.symmetric(
            vertical: 8,
            horizontal: MediaQuery.of(context).size.width > 600 ? 0 : 12,
          ),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isBestValue ? Colors.purple.shade200 : Colors.grey.shade200,
              width: isBestValue ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isBestValue
                    ? Colors.purple.shade100.withOpacity(0.5)
                    : Colors.grey.shade100,
                blurRadius: 8,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                    decoration: BoxDecoration(
                      color: cardAccentColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      subscriptionType.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: subscriptionType == 'pro'
                            ? Colors.blue.shade700
                            : Colors.purple.shade700,
                      ),
                    ),
                  ),
                  if (isBestValue)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'BEST VALUE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                        fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      interval,
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 14),
                    ),
                  ),
                ],
              ),
              Text(
                trialPeriod,
                style: TextStyle(
                  color:
                      subscriptionType == 'pro' ? Colors.blue : Colors.purple,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Features:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...features.map((feature) => _buildFeatureItem(feature,
                  isHighlighted: isBestValue &&
                      features.indexOf(feature) >= proFeatures.length)),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor:
                      subscriptionType == 'pro' ? Colors.blue : Colors.purple,
                  minimumSize: const Size(double.infinity, 48),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: isLoading
                    ? null
                    : () async {
                        setState(() {
                          isLoading = true;
                        });
                        final FirebaseAuth auth = FirebaseAuth.instance;
                        User? currentUser = auth.currentUser;

                        if (currentUser == null) {
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const LoginScreen(),
                            ),
                          );
                        } else {
                          try {
                            await CheckoutSessionManager()
                                .createCheckoutSession(
                                    context, subscriptionType, periodType);
                          } catch (e) {
                            print('Error creating checkout session: $e');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content: Text(
                                      'Error creating checkout session: $e')),
                            );
                          }
                        }
                        setState(() {
                          isLoading = false;
                        });
                      },
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Get Started with ${subscriptionType == 'pro' ? 'Pro' : 'Business'}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold),
                      ),
              ),
              if (isLoading)
                const Padding(
                  padding: EdgeInsets.only(top: 6.0),
                  child: Center(
                    child: Text(
                      'Processing your request...',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ),
                ),
              if (periodType == 'yearly')
                Padding(
                  padding: const EdgeInsets.only(top: 10.0),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Save 16% with annual billing',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFeatureItem(String text, {bool isHighlighted = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isHighlighted
                  ? Colors.purple.shade100
                  : Colors.green.shade100,
            ),
            padding: const EdgeInsets.all(3),
            child: Icon(
              Icons.check,
              color: isHighlighted ? Colors.purple : Colors.green,
              size: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: isHighlighted ? Colors.black87 : Colors.black54,
                fontWeight: isHighlighted ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
