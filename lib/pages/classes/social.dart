// ignore_for_file: deprecated_member_use, avoid_print, library_private_types_in_public_api, depend_on_referenced_packages, use_build_context_synchronously
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sizer/sizer.dart';
import 'package:yoobble/models/tab_controller.dart'; // Assuming you have this extension
import '../../models/groq_API.dart';
import '../../models/quotas.dart';
import '../../stripe/paywall.dart';
import '../../stripe/stripeinfo.dart';
import '../../utils/responsive.dart';
import 'based_class.dart';

class SocialMediaGenerator extends BaseGenerator {
  const SocialMediaGenerator({
    super.key,
  });

  @override
  _SocialMediaGeneratorState createState() => _SocialMediaGeneratorState();
}

class _SocialMediaGeneratorState
    extends BaseGeneratorState<SocialMediaGenerator>
    with SingleTickerProviderStateMixin {
  final TextEditingController topicController = TextEditingController();
  final TextEditingController messageController = TextEditingController();
  final TextEditingController keywordController = TextEditingController();
  final TextEditingController hashtagController = TextEditingController();
  final TextEditingController callToActionController = TextEditingController();

  // TabController for mobile view
  late TabController _tabController;

  String selectedPlatform = 'LinkedIn';
  String selectedTone = 'Professional';
  String selectedGoal = 'Engagement';
  String selectedLength = 'Standard';
  String? _errorMessage; // Added for displaying errors

  // Radio button states
  bool includeHashtags = false;
  bool includeSeoKeywords = false;

  final List<String> platforms = [
    'LinkedIn',
    'Facebook',
    'Instagram',
    'Twitter',
    'TikTok',
    'Pinterest',
    'YouTube'
  ];

  @override
  final List<String> tones = [
    'Professional',
    'Friendly',
    'Persuasive',
    'Informative',
    'Humorous',
    'Inspirational',
    'Emotional'
  ];

  final List<String> postGoals = [
    'Engagement',
    'Sales',
    'Brand Awareness',
    'Web Traffic',
    'Lead Generation',
    'Authority Building',
    'Entertainment'
  ];

  final List<String> postLengths = ['Very Short', 'Short', 'Standard', 'Long'];

  // Color scheme
  final Color primaryColor = Colors.black;
  final Color secondaryColor = Color(0xFFF59E0B); // Amber/gold
  final Color accentColor = Color.fromARGB(255, 1, 28, 72); // Vibrant blue
  final Color backgroundColor = Color(0xFFF9FAFB); // Light gray
  final Color cardColor = Colors.white;
  final Color textColor = Color(0xFF1F2937); // Dark gray
  final Color lightTextColor = Color(0xFF6B7280); // Medium gray

  // --- Subscription Variables ---
  String? userSubscriptionPlan;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  bool _isTrialActive = false;
  DateTime? _trialEndDate;
  bool _isSubscribed = false; // Combined check for active/trial
  bool _isSubscriptionLoading = true;
  String? customerId;
  // --- End Subscription Variables ---

  // --- Quota Variables ---
  final ApiQuotaManager _quotaManager = ApiQuotaManager();
  int _remainingQuota = 0;
  int _dailyLimit = ApiQuotaManager.dailyLimit; // Default limit
  bool _isLoadingQuota = true;
  bool _hasUnlimitedQuota =
      false; // Flag for unlimited quota (Standard/Business)
  // --- End Quota Variables ---

  @override
  void initState() {
    super.initState();
    // Initialize TabController for mobile view
    _tabController = TabController(length: 2, vsync: this);
    // Load subscription status
    _checkUserSubscription();
    _checkSubscriptionStatus(); // Also calls quota refresh internally
    // Load quota information initially (will be refreshed after sub check)
    _loadRemainingQuota();
    _loadCurrentDailyLimit();
  }

  @override
  void dispose() {
    topicController.dispose();
    messageController.dispose();
    keywordController.dispose();
    hashtagController.dispose();
    callToActionController.dispose();
    _tabController.dispose(); // Dispose TabController
    super.dispose();
  }

  // --- Quota Management Methods ---
  Future<void> _loadRemainingQuota() async {
    setState(() {
      _isLoadingQuota = true;
    });

    try {
      final remaining = await _quotaManager.getRemainingQuota();
      setState(() {
        _remainingQuota = remaining;
        _hasUnlimitedQuota = remaining == -1; // Set unlimited flag
        _isLoadingQuota = false;
      });
    } catch (e) {
      setState(() {
        _remainingQuota = 0;
        _hasUnlimitedQuota = false; // Ensure flag is reset on error
        _isLoadingQuota = false;
      });
      print('Error loading quota: $e');
    }
  }

  // Load the current daily limit based on subscription plan
  Future<void> _loadCurrentDailyLimit() async {
    try {
      final limit = await _quotaManager.getCurrentDailyLimit();
      setState(() {
        _dailyLimit = limit;
      });
    } catch (e) {
      print('Error loading daily limit: $e');
      // Keep default value on error
    }
  }
  // --- End Quota Management Methods ---

  // --- Subscription Check Methods ---
  Future<String?> _getCustomerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final data = userData.data() as Map<String, dynamic>?;
        if (data != null && data.containsKey('customerId')) {
          return data['customerId'] as String?;
        }
      } catch (e) {
        print("Error fetching customer ID from Firestore: $e");
      }
    }
    return null;
  }

  Future<void> _checkSubscriptionStatus() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      customerId = await _getCustomerId(); // Fetch or update customerId

      if (user == null || customerId == null || customerId!.isEmpty) {
        print("User not logged in or no customer ID found.");
        if (mounted) {
          setState(() {
            _isSubscribed = false;
            _isTrialActive = false;
            userSubscriptionPlan = null;
            _isSubscriptionLoading = false; // Ensure loading stops
          });
          // Refresh quota/limit after determining no subscription
          await _loadRemainingQuota();
          await _loadCurrentDailyLimit();
        }
        return; // Exit early
      }

      // Fetch subscription details from Stripe
      final url = Uri.parse(
          'https://api.stripe.com/v1/customers/$customerId/subscriptions');
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $stripeSecretKey',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
      );

      bool wasSubscribed = false;
      bool wasTrial = false;
      String? fetchedPlan;
      DateTime? fetchedTrialEnd;

      if (response.statusCode == 200) {
        final subscriptions = jsonDecode(response.body);
        if (subscriptions.containsKey('data') &&
            subscriptions['data'] is List) {
          final subsList = subscriptions['data'] as List;
          final activeOrTrialSubs = subsList.where((sub) =>
              sub is Map &&
              (sub['status'] == 'active' || sub['status'] == 'trialing'));

          if (activeOrTrialSubs.isNotEmpty) {
            final subscription = activeOrTrialSubs.first;
            final productId = subscription['plan']['product'];
            wasSubscribed = true; // User has an active or trial subscription

            if (subscription['status'] == 'trialing') {
              final trialEndTimestamp = subscription['trial_end'];
              if (trialEndTimestamp != null) {
                fetchedTrialEnd = DateTime.fromMillisecondsSinceEpoch(
                    trialEndTimestamp * 1000);
                // Check if trial is still valid
                if (fetchedTrialEnd.isAfter(DateTime.now())) {
                  wasTrial = true;
                } else {
                  wasTrial = false; // Trial expired
                  print("Trial period ended.");
                }
              }
            }
            fetchedPlan = await _fetchProductName(productId);
          } else {
            print("No active or trialing subscriptions found.");
          }
        } else {
          print('Stripe response format unexpected: ${response.body}');
        }
      } else if (response.statusCode == 404) {
        print(
            "Customer $customerId not found on Stripe or has no subscriptions.");
      } else {
        print(
            'Stripe API error fetching subscriptions: ${response.statusCode} ${response.body}');
      }

      // Update state only if mounted
      if (mounted) {
        setState(() {
          _isSubscribed = wasSubscribed; // True if active or trial exists
          _isTrialActive = wasTrial;
          _trialEndDate = fetchedTrialEnd;
          userSubscriptionPlan = fetchedPlan; // Can be null if not subscribed
          _isSubscriptionLoading = false;
        });

        // Refresh quota after subscription check
        await _loadRemainingQuota();
        await _loadCurrentDailyLimit();
      }
    } catch (e) {
      print('Error checking subscription status: $e');
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _isTrialActive = false;
          userSubscriptionPlan = null;
          _isSubscriptionLoading = false; // Ensure loading stops on error
        });
        // Still refresh quota/limit even on error
        await _loadRemainingQuota();
        await _loadCurrentDailyLimit();
      }
    }
  }

  Future<String> _fetchProductName(String productId) async {
    if (stripeSecretKey.isEmpty) {
      print("Stripe secret key is missing.");
      return 'Unknown';
    }
    final url = Uri.parse('https://api.stripe.com/v1/products/$productId');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $stripeSecretKey'},
      );

      if (response.statusCode == 200) {
        final product = jsonDecode(response.body);
        final productName =
            product['name'] as String?; // Product name might be null

        if (productName == null) return 'Unknown';

        // Determine plan based on name conventions
        if (productName.toLowerCase().contains('standard')) {
          return 'Standard';
        } else if (productName.toLowerCase().contains('pro')) {
          return 'Pro';
        } else if (productName.toLowerCase().contains('business')) {
          return 'Business';
        } else {
          print("Product name '$productName' doesn't match known plans.");
          return 'Unknown'; // Or return productName directly if preferred
        }
      } else {
        print(
            'Error fetching product name from Stripe: ${response.statusCode} - ${response.body}');
        return 'Unknown';
      }
    } catch (e) {
      print("Error during HTTP request to fetch product name: $e");
      return 'Unknown';
    }
  }

  Future<void> _checkUserSubscription() async {
    setState(() {
      _isSubscriptionLoading = true; // Start loading
    });
    customerId = await _getCustomerId();
    if (customerId != null) {
      // _checkSubscriptionStatus will fetch the plan name and update state
      // and trigger quota refreshes
      await _checkSubscriptionStatus();
    } else {
      // If no customerId, definitely not subscribed
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _isTrialActive = false;
          userSubscriptionPlan = null;
          _isSubscriptionLoading = false;
        });
        // Refresh quota/limit after determining no subscription
        await _loadRemainingQuota();
        await _loadCurrentDailyLimit();
      }
    }
  }

  // Getter for remaining trial days
  String get _getRemainingTrialDays {
    if (!_isTrialActive || _trialEndDate == null) return "0";
    final difference = _trialEndDate!.difference(DateTime.now());
    // Return 0 if difference is negative or zero
    return difference.inDays > 0 ? difference.inDays.toString() : "0";
  }
  // --- End Subscription Check Methods ---

  // --- Upgrade Dialog and Navigation ---
  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: primaryColor, // Use generator's primary color
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium,
                          color: Colors.white, size: 28),
                      SizedBox(width: 15),
                      Text(
                        'Upgrade Required', // More generic title
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Courier',
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Conditionally show trial info if applicable
                      if (_isTrialActive)
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.amber[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.amber),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timer, color: Colors.amber[800]),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You have $_getRemainingTrialDays days left in your trial.',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    color: Colors.amber[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Show Pro-specific message if applicable
                      else if (userSubscriptionPlan == 'Pro')
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            // Use accentColor or a purple shade for Pro
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: accentColor),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: accentColor),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    color: accentColor, // Use accent color
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Show standard message for free users or unknown state
                      else
                        Text(
                          'This feature requires an active subscription or available quota.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontFamily: 'Courier',
                          ),
                        ),
                      SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                            child: Text(
                              'Maybe Later',
                              style: TextStyle(
                                color: Colors.grey[700],
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: _handleSubscriptionNavigation,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 3,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upgrade, color: Colors.white),
                                SizedBox(width: 8),
                                Text(
                                  'View Plans',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleSubscriptionNavigation() async {
    // Close the upgrade dialog first
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }

    // Show loading dialog while re-checking status
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: primaryColor),
                SizedBox(width: 20),
                Text("Checking Subscription..."),
              ],
            ),
          ),
        );
      },
    );

    // Re-check subscription status
    await _checkSubscriptionStatus(); // This updates _isSubscribed & plan

    // Close the loading dialog
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // Navigate based on the updated status
    if (!context.mounted) return; // Check context validity after async gap

    if (_isSubscribed) {
      // Navigate to info page if subscribed (active or trial)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionInfoPage(),
        ),
      );
    } else {
      // Navigate to paywall if not subscribed
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionBottomSheet(),
        ),
      );
    }
  }
  // --- End Upgrade Dialog and Navigation ---

  // --- Helper to build Status Chip ---
  Widget _buildStatusChip() {
    // Loading state
    if (_isSubscriptionLoading || _isLoadingQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: Text("..."), // Simple indicator during load
          ),
        ),
      );
    }

    // Standard and Business Plans (Unlimited)
    if (userSubscriptionPlan != null &&
        (userSubscriptionPlan == 'Standard' ||
            userSubscriptionPlan == 'Business')) {
      Color chipColor = Colors.grey[200]!;
      Color textColorValue = Colors.black87;
      IconData icon = Icons.check_circle_outline; // Default icon

      switch (userSubscriptionPlan) {
        case 'Standard':
          chipColor = Colors.blue[100]!;
          textColorValue = Colors.blue[800]!;
          icon = Icons.star_border;
          break;
        case 'Business':
          chipColor = Colors.green[100]!;
          textColorValue = Colors.green[800]!;
          icon = Icons.business;
          break;
      }

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            avatar: Icon(icon, size: 16, color: textColorValue),
            label: Text(
              '$userSubscriptionPlan Plan',
              style: TextStyle(
                  color: textColorValue,
                  fontWeight: FontWeight.bold,
                  fontSize: 11),
            ),
            backgroundColor: chipColor,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Pro Plan (Specific Quota)
    if (userSubscriptionPlan == 'Pro') {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            avatar: Icon(Icons.star, size: 16, color: accentColor),
            label: Text(
              'Pro $_remainingQuota/${ApiQuotaManager.proDailyLimit}',
              style: TextStyle(
                color: accentColor, // Use accent color for Pro
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            backgroundColor:
                accentColor.withOpacity(0.2), // Use accent color shade
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Free Plan (or unknown/no subscription) - Show remaining free quota
    // _hasUnlimitedQuota check ensures we don't show this for Standard/Business
    if (!_hasUnlimitedQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            label: Text(
              '$_remainingQuota/$_dailyLimit', // Use _dailyLimit (which is correctly set for free users)
              style: TextStyle(
                color: _remainingQuota < 5 ? Colors.white : textColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            backgroundColor: _remainingQuota < 5
                ? Colors.red[700]
                : (_remainingQuota < 10 ? Colors.orange : Colors.grey[200]),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Fallback/Default Chip (should ideally not be reached if logic is correct)
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        child: Chip(
          label: Text(
            '...',
            style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.bold,
                fontSize: 11),
          ),
          backgroundColor: Colors.grey[200],
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
        ),
      ),
    );
  }
  // --- End Helper ---

  @override
  Widget build(BuildContext context) {
    // Common AppBar Actions for both mobile and desktop
    List<Widget> appBarActions = [
      _buildStatusChip(), // Display subscription or quota status
    ];

    return ResponsiveWidget(
      // --- Mobile View ---
      mobile: Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          automaticallyImplyLeading:
              false, // Ne met rien par défaut (comme le bouton retour)
          backgroundColor: cardColor,
          surfaceTintColor: cardColor,
          elevation: 1, // Add slight elevation for mobile
          shadowColor: Colors.grey.withOpacity(0.1),
          // Title for mobile can be the generator name
          title: Text(
            "Social Media Post", // Use the title passed to the widget
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 18, // Suitable size for mobile AppBar
            ),
          ),
          centerTitle: false, // Align title to the left
          iconTheme: IconThemeData(color: textColor), // Back button color
          actions: appBarActions, // Use the common actions
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Options'),
              Tab(text: 'Results'),
            ],
            labelColor: Colors.black,
            unselectedLabelColor: Colors.black,
            indicatorColor: Colors.black,
          ),
        ),
        body: SafeArea(
          // Ensure content avoids notches/status bar
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Form/Options
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Card(
                      color: cardColor,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: buildForm(),
                      ),
                    ),
                  ],
                ),
              ),

              // Tab 2: Generated Content Results
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Card(
                      elevation: 0,
                      color: cardColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        height: 70.h, // Fixed height for results on mobile
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header for results
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color:
                                            _getPlatformColor(selectedPlatform)
                                                .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        _getPlatformIcon(selectedPlatform),
                                        color:
                                            _getPlatformColor(selectedPlatform),
                                        size: 16,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Generated Post',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                      ),
                                    ),
                                  ],
                                ),
                                // Action buttons
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                          isEditing ? Icons.check : Icons.edit,
                                          color: lightTextColor,
                                          size: 20),
                                      onPressed: () => setState(() {
                                        isEditing = !isEditing;
                                      }),
                                      tooltip:
                                          isEditing ? 'Finish Editing' : 'Edit',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                          isCopied ? Icons.check : Icons.copy,
                                          color: isCopied
                                              ? Colors.green
                                              : lightTextColor,
                                          size: 20),
                                      onPressed: () {
                                        final textToCopy = isEditing
                                            ? generatedContentController.text
                                            : generatedContent;
                                        if (textToCopy.isNotEmpty) {
                                          copyToClipboard(textToCopy);
                                        }
                                      },
                                      tooltip: isCopied ? 'Copied' : 'Copy',
                                    ),
                                    IconButton(
                                      icon: Icon(
                                          isSaved
                                              ? Icons.check
                                              : Icons.save_outlined,
                                          color: isSaved
                                              ? Colors.green
                                              : lightTextColor,
                                          size: 20),
                                      onPressed: saveContent,
                                      tooltip: isSaved ? 'Saved' : 'Save',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(height: 16),
                            // Preview/edit area
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                padding: EdgeInsets.all(12),
                                child: isEditing
                                    ? TextField(
                                        controller: generatedContentController,
                                        maxLines: null,
                                        expands: true,
                                        decoration: InputDecoration.collapsed(
                                          hintText: 'Generated post text...',
                                          hintStyle: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 14),
                                        ),
                                        style: TextStyle(
                                            fontSize: 14,
                                            height: 1.5,
                                            color: textColor),
                                      )
                                    : isGenerating
                                        ? Center(
                                            child: CircularProgressIndicator(
                                                color: primaryColor))
                                        : SingleChildScrollView(
                                            child: generatedContent.isEmpty
                                                ? Center(
                                                    child: Text(
                                                        'Social media post content appears here.',
                                                        style: TextStyle(
                                                            color: Colors
                                                                .grey[400])))
                                                : Text(generatedContent,
                                                    style: TextStyle(
                                                        fontSize: 14,
                                                        height: 1.5,
                                                        color: textColor)),
                                          ),
                              ),
                            ),
                            // Badges
                            if (generatedContent.isNotEmpty && !isGenerating)
                              Container(
                                margin: EdgeInsets.only(top: 12),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    _buildBadge(
                                      selectedPlatform,
                                      _getPlatformIcon(selectedPlatform),
                                      _getPlatformColor(selectedPlatform),
                                    ),
                                    _buildBadge(
                                      selectedGoal,
                                      FontAwesomeIcons.bullseye,
                                      secondaryColor,
                                    ),
                                    _buildBadge(
                                      selectedTone,
                                      FontAwesomeIcons.commentDots,
                                      accentColor,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),

      // --- Desktop View ---
      desktop: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading:
              false, // Ne met rien par défaut (comme le bouton retour)
          shadowColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.white,
          backgroundColor: Colors.white,
          actions: appBarActions,
        ),
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left side - Form
            Expanded(
              flex: 2,
              child: Card(
                color: cardColor,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: SingleChildScrollView(
                        child: buildForm(),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            SizedBox(width: 2.w),

            // Right side - Generated content
            Expanded(
              flex: 3,
              child: Card(
                elevation: 0,
                color: cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Container(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header of the right side
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _getPlatformColor(selectedPlatform)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _getPlatformIcon(selectedPlatform),
                                  color: _getPlatformColor(selectedPlatform),
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                ' $selectedPlatform',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Edit button
                              AnimatedContainer(
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isEditing
                                      ? primaryColor.withOpacity(0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isEditing
                                        ? primaryColor
                                        : Colors.transparent,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      isEditing = !isEditing;
                                      if (!isEditing &&
                                          generatedContent.isNotEmpty) {
                                        generatedContentController.text =
                                            generatedContent;
                                      }
                                    });
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        isEditing ? Icons.check : Icons.edit,
                                        color: isEditing
                                            ? primaryColor
                                            : lightTextColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        isEditing ? 'Finish' : 'Edit',
                                        style: TextStyle(
                                          color: isEditing
                                              ? primaryColor
                                              : lightTextColor,
                                          fontWeight: isEditing
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              // Copy button
                              AnimatedContainer(
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isCopied
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isCopied
                                        ? Colors.green
                                        : Colors.transparent,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    final textToCopy = isEditing
                                        ? generatedContentController.text
                                        : generatedContent;
                                    if (textToCopy.isNotEmpty) {
                                      copyToClipboard(textToCopy);
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        isCopied ? Icons.check : Icons.copy,
                                        color: isCopied
                                            ? Colors.green
                                            : lightTextColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        isCopied ? 'Copied' : 'Copy',
                                        style: TextStyle(
                                          color: isCopied
                                              ? Colors.green
                                              : lightTextColor,
                                          fontWeight: isCopied
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(width: 8),
                              // Save button
                              AnimatedContainer(
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                padding: EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSaved
                                      ? Colors.green.withOpacity(0.1)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSaved
                                        ? Colors.green
                                        : Colors.transparent,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    saveContent();
                                  },
                                  child: Row(
                                    children: [
                                      Icon(
                                        isSaved ? Icons.check : Icons.save,
                                        color: isSaved
                                            ? Colors.green
                                            : lightTextColor,
                                        size: 18,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        isSaved ? 'Saved' : 'Save',
                                        style: TextStyle(
                                          color: isSaved
                                              ? Colors.green
                                              : lightTextColor,
                                          fontWeight: isSaved
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 24),

                      // Preview/edit area
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: EdgeInsets.all(24),
                          child: isEditing
                              ? TextField(
                                  controller: generatedContentController,
                                  maxLines: null,
                                  expands: true,
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText:
                                        'The generated post will appear here...',
                                    hintStyle:
                                        TextStyle(color: Colors.grey[400]),
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    height: 1.6,
                                    color: textColor,
                                  ),
                                )
                              : isGenerating
                                  ? Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            color: primaryColor,
                                            strokeWidth: 3,
                                          ),
                                          SizedBox(height: 24),
                                          Text(
                                            'Creating your perfect social media post...',
                                            style: TextStyle(
                                              color: primaryColor,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          SizedBox(height: 8),
                                          Text(
                                            'This may take a minute',
                                            style: TextStyle(
                                              color: lightTextColor,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : SingleChildScrollView(
                                      child: generatedContent.isEmpty
                                          ? Center(
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    FontAwesomeIcons.penFancy,
                                                    size: 40,
                                                    color: Colors.grey[300],
                                                  ),
                                                  SizedBox(height: 24),
                                                  Text(
                                                    'Your social media post will appear here',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey[400],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Fill in the form and click "Generate Post" to create your content',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[400],
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : Text(
                                              generatedContent,
                                              style: TextStyle(
                                                fontSize: 16,
                                                height: 1.6,
                                                color: textColor,
                                              ),
                                            ),
                                    ),
                        ),
                      ),

                      // Platform, goal, and tone badges
                      if (generatedContent.isNotEmpty && !isGenerating)
                        Container(
                          margin: EdgeInsets.only(top: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildBadge(
                                selectedPlatform,
                                _getPlatformIcon(selectedPlatform),
                                _getPlatformColor(selectedPlatform),
                              ),
                              _buildBadge(
                                selectedGoal,
                                FontAwesomeIcons.bullseye,
                                secondaryColor,
                              ),
                              _buildBadge(
                                selectedTone,
                                FontAwesomeIcons.commentDots,
                                accentColor,
                              ),
                              _buildBadge(
                                selectedLength,
                                FontAwesomeIcons.rulerHorizontal,
                                Color(0xFF10B981), // Emerald green
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper method to create a badge
  Widget _buildBadge(String text, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withOpacity(0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: color,
          ),
          SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // Obtenir la couleur associée à la plateforme
  Color _getPlatformColor(String platform) {
    switch (platform) {
      case 'LinkedIn':
        return Color(0xFF0077B5);
      case 'Facebook':
        return Color(0xFF1877F2);
      case 'Instagram':
        return Color(0xFFE1306C);
      case 'Twitter':
        return Color(0xFF1DA1F2);
      case 'TikTok':
        return Color(0xFF000000);
      case 'Pinterest':
        return Color(0xFFE60023);
      case 'YouTube':
        return Color(0xFFFF0000);
      default:
        return Colors.grey;
    }
  }

  // Obtenir l'icône associée à la plateforme
  IconData _getPlatformIcon(String platform) {
    switch (platform) {
      case 'LinkedIn':
        return FontAwesomeIcons.linkedin;
      case 'Facebook':
        return FontAwesomeIcons.facebook;
      case 'Instagram':
        return FontAwesomeIcons.instagram;
      case 'Twitter':
        return FontAwesomeIcons.twitter;
      case 'TikTok':
        return FontAwesomeIcons.tiktok;
      case 'Pinterest':
        return FontAwesomeIcons.pinterest;
      case 'YouTube':
        return FontAwesomeIcons.youtube;
      default:
        return FontAwesomeIcons.globe;
    }
  }

  // Radio button widget for toggles
  Widget _buildRadioOption(
      {required String title,
      required IconData icon,
      required bool value,
      required Function(bool) onChanged}) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: value ? primaryColor.withOpacity(0.05) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value ? primaryColor : Colors.grey[300]!,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: value ? primaryColor : Colors.grey[600],
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: value ? FontWeight.bold : FontWeight.normal,
                  color: value ? primaryColor : textColor,
                  fontSize: 14,
                ),
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: value ? primaryColor : Colors.grey[400]!,
                  width: 2,
                ),
              ),
              child: value
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Form header
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryColor.withOpacity(0.8),
                accentColor.withOpacity(0.8)
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.3),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FontAwesomeIcons.shareNodes,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create Engaging Social Posts',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tailored content for each platform to maximize engagement',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 28),

        // Platform and goal
        buildSectionHeader('Platform & Goal', FontAwesomeIcons.bullseye),
        SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: buildDropdown(
                label: 'Platform',
                value: selectedPlatform,
                items: platforms,
                onChanged: (value) {
                  setState(() {
                    selectedPlatform = value!;
                  });
                },
                icon: FontAwesomeIcons.globe,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Post Goal',
                value: selectedGoal,
                items: postGoals,
                onChanged: (value) {
                  setState(() {
                    selectedGoal = value!;
                  });
                },
                icon: FontAwesomeIcons.bullseye,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        // Content
        buildSectionHeader('Content', FontAwesomeIcons.pencilAlt),
        SizedBox(height: 20),

        buildTextField(
          controller: topicController,
          label: 'Post Topic',
          hint: 'What is your post about?',
          icon: FontAwesomeIcons.lightbulb,
          required: true,
        ),
        SizedBox(height: 16),

        buildTextField(
          controller: messageController,
          label: 'Main Message',
          hint: 'What key message do you want to communicate?',
          icon: FontAwesomeIcons.message,
          maxLines: 3,
          required: true,
        ),
        SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: buildDropdown(
                label: 'Tone',
                value: selectedTone,
                items: tones,
                onChanged: (value) {
                  setState(() {
                    selectedTone = value!;
                  });
                },
                icon: FontAwesomeIcons.commentDots,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Length',
                value: selectedLength,
                items: postLengths,
                onChanged: (value) {
                  setState(() {
                    selectedLength = value!;
                  });
                },
                icon: FontAwesomeIcons.rulerHorizontal,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        // Keywords and hashtags
        buildSectionHeader('Keywords & Hashtags', FontAwesomeIcons.hashtag),
        SizedBox(height: 20),

        buildTextField(
          controller: keywordController,
          label: 'Keywords (comma separated)',
          hint: 'Important terms to include in your post',
          icon: FontAwesomeIcons.key,
        ),
        SizedBox(height: 16),

        // Hashtag toggle
        _buildRadioOption(
          title: 'Include Hashtags',
          icon: FontAwesomeIcons.hashtag,
          value: includeHashtags,
          onChanged: (value) {
            setState(() {
              includeHashtags = value;
            });
          },
        ),
        SizedBox(height: 12),

        // Show hashtag field only if includeHashtags is true
        if (includeHashtags) ...[
          buildTextField(
            controller: hashtagController,
            label: 'Hashtags (without #, space separated)',
            hint: 'marketing socialmedia strategy digital',
            icon: FontAwesomeIcons.hashtag,
          ),
          SizedBox(height: 16),
        ],

        // SEO Keywords toggle
        _buildRadioOption(
          title: 'Include SEO Keywords',
          icon: FontAwesomeIcons.searchengin,
          value: includeSeoKeywords,
          onChanged: (value) {
            setState(() {
              includeSeoKeywords = value;
            });
          },
        ),
        SizedBox(height: 16),

        // Call to action
        buildSectionHeader('Call to Action', FontAwesomeIcons.handPointer),
        SizedBox(height: 20),

        buildTextField(
          controller: callToActionController,
          label: 'Call to Action',
          hint: 'What do you want readers to do after reading your post?',
          icon: FontAwesomeIcons.bullhorn,
        ),
        SizedBox(height: 28),

        // Warning message if error
        if (_errorMessage != null)
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red[800],
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Quota indicator - Limit Reached (handles both Free and Pro)
        if (!_isLoadingQuota && !_hasUnlimitedQuota && _remainingQuota == 0)
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                Icon(Icons.warning, color: Colors.red),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Daily Limit Reached',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red[800],
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        userSubscriptionPlan == 'Pro'
                            ? 'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.'
                            : 'You\'ve reached your daily free limit of ${ApiQuotaManager.dailyLimit} generations. Upgrade to a paid plan for increased or unlimited access.',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Quota indicator - Remaining Quota (handles both Free and Pro < 5)
        if (!_isLoadingQuota &&
            !_hasUnlimitedQuota &&
            _remainingQuota > 0 &&
            (_remainingQuota < 5 || userSubscriptionPlan == 'Pro'))
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              // Amber for Free users < 5, Blue (accent) for Pro users
              color: _remainingQuota < 5 && userSubscriptionPlan != 'Pro'
                  ? Colors.amber.withOpacity(0.1)
                  : accentColor.withOpacity(0.1), // Blue shade for Pro
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _remainingQuota < 5 && userSubscriptionPlan != 'Pro'
                    ? Colors.amber
                    : accentColor, // Blue border for Pro
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: _remainingQuota < 5 && userSubscriptionPlan != 'Pro'
                      ? Colors.amber[800]
                      : accentColor, // Blue icon for Pro
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    userSubscriptionPlan == 'Pro'
                        ? 'You have $_remainingQuota/${ApiQuotaManager.proDailyLimit} Pro generations remaining today.'
                        : 'You have $_remainingQuota/${ApiQuotaManager.dailyLimit} free generations remaining today.',
                    style: TextStyle(
                      color:
                          _remainingQuota < 5 && userSubscriptionPlan != 'Pro'
                              ? Colors.amber[800]
                              : accentColor, // Blue text for Pro
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Generate button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed:
                // Disable if generating OR if quota is 0 AND user has no unlimited access
                (isGenerating || (_remainingQuota == 0 && !_hasUnlimitedQuota))
                    ? null
                    : generateContent,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: primaryColor.withOpacity(0.6),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isGenerating)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                if (!isGenerating)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FontAwesomeIcons.wandMagicSparkles,
                          color: Colors.white, size: 18),
                      SizedBox(width: 12),
                      Text(
                        'Generate Post',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: primaryColor,
            size: 16,
          ),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }

  @override
  Widget buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool required = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            SizedBox(width: 4),
            if (required)
              Text(
                '*',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            style: TextStyle(
              fontSize: 15,
              color: textColor,
            ),
            decoration: InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontSize: 15,
              ),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 18,
                ),
              ),
              border: InputBorder.none,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget buildDropdown({
    required String label,
    required String value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11, // Reduced size
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!),
          ),
          padding: EdgeInsets.only(
              left: 16, right: 12), // Adjust padding for icon alignment
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon:
                  Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
              style: TextStyle(
                  color: textColor,
                  fontSize: 11, // Consistent reduced size
                  fontFamily: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.fontFamily), // Use theme font
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Add prefix icon inside items for alignment
              selectedItemBuilder: (BuildContext context) {
                return items.map<Widget>((String item) {
                  // Added Flexible and TextOverflow.ellipsis for safety
                  return Row(
                    children: [
                      Icon(icon, color: primaryColor, size: 18),
                      SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          item,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  );
                }).toList();
              },
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item,
                      style: TextStyle(
                          fontSize: 12)), // Slightly larger in dropdown list
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void copyToClipboard(String text) async {
    // Fixed copying functionality
    await Clipboard.setData(ClipboardData(text: text));
    setState(() {
      isCopied = true;
    });
    // Reset after 2 seconds
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isCopied = false;
        });
      }
    });
    // Show snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Content copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green[700],
      ),
    );
  }

  @override
  void generateContent() async {
    setState(() {
      _errorMessage = null;
    }); // Clear previous errors

    // Basic validation
    if (topicController.text.trim().isEmpty ||
        messageController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all required fields (*)';
      });
      showErrorSnackBar(
          'Please fill in at least the Topic and Main Message'); // Also show snackbar
      return;
    }

    // Check if user can make API request based on quota (handles all plans)
    final canMakeRequest = await _quotaManager.canMakeApiRequest();
    if (!canMakeRequest) {
      setState(() {
        // Set specific error message based on plan
        _errorMessage = userSubscriptionPlan == 'Pro'
            ? "You've reached your Pro plan daily limit. Upgrade to Standard or Business for unlimited access."
            : "You've reached your daily free limit. Upgrade to continue.";
      });
      _showUpgradeDialog(); // Show upgrade dialog
      return;
    }

    setState(() {
      isGenerating = true;
      generatedContent = '';
    });

    try {
      final prompt = _buildAIPrompt();
      final response = await _groqApiService.generateContent(prompt);

      // Record API usage only for users with limited quota (Free and Pro)
      if (!_hasUnlimitedQuota) {
        await _quotaManager.recordApiUsage();
        await _loadRemainingQuota(); // Refresh quota count in UI
      }

      setState(() {
        generatedContent = response.trim(); // Trim whitespace
        generatedContentController.text = response.trim();
        isGenerating = false;
        isCopied = false; // Reset copy/save state
        isSaved = false;
        isEditing = false;
      });
      // Use the mixin to navigate if on mobile
      _tabController.navigateToResultsTabIfMobile(context);
    } catch (e) {
      print('Error during API call: $e');
      setState(() {
        isGenerating = false;
        _errorMessage = 'Failed to generate content. Error: ${e.toString()}';
      });
      showErrorSnackBar('Error during generation: ${e.toString()}');
    }
  }

  // Build the prompt for the AI API with platform-specific customization
  String _buildAIPrompt() {
    final String topic = topicController.text;
    final String message = messageController.text;
    final String keywords = keywordController.text;
    final String hashtags = hashtagController.text;
    final String cta = callToActionController.text;

    // Platform-specific instructions
    String platformSpecificPrompt = '';
    switch (selectedPlatform) {
      case 'LinkedIn':
        platformSpecificPrompt = '''
        - Focus on professional insights and expertise.
        - Make it suitable for a business audience.
        - Keep it formal yet conversational.
        - Incorporate industry-specific terminology when relevant.
        - Consider including a professional call to action like connecting, following, or reading more.
        ''';
        break;
      case 'Facebook':
        platformSpecificPrompt = '''
        - Create a conversational tone that encourages dialogue.
        - Consider including a question to boost engagement.
        - Make it visually descriptive to accompany images.
        - Focus on community and connection aspects.
        - Keep paragraphs short and easy to read on mobile.
        ''';
        break;
      case 'Instagram':
        platformSpecificPrompt = '''
        - Create visually evocative text that complements photos or videos.
        - Make the first two lines especially catchy (visible before "more" button).
        - Include emojis where appropriate.
        - Ensure hashtags are strategic and relevant.
        - Focus on lifestyle, aesthetics, or inspirational elements.
        ''';
        break;
      case 'Twitter':
        platformSpecificPrompt = '''
        - Create concise, impactful content that fits within character limits.
        - Focus on the most compelling aspect of the message.
        - Use crisp language with strong verbs.
        - Make it easily shareable (retweetable) with a clear hook.
        - Leave room for relevant hashtags and user mentions if needed.
        ''';
        break;
      case 'TikTok':
        platformSpecificPrompt = '''
        - Create short, punchy text that would accompany a video.
        - Keep it extremely casual, trendy, and approachable.
        - Use trending phrases or meme references when appropriate, but ensure they fit the topic.
        - Focus on hooking viewers in the first few words.
        - Include relevant sound or challenge references if applicable.
        ''';
        break;
      case 'Pinterest':
        platformSpecificPrompt = '''
        - Focus on inspirational, aspirational, or instructional content.
        - Make it search-friendly with relevant keywords.
        - Create text that complements a strong visual Pin (image or video).
        - Focus on DIY, how-to, recipe, or inspirational angles.
        - Include a clear benefit or takeaway for the reader.
        ''';
        break;
      case 'YouTube':
        platformSpecificPrompt = '''
        - Create text suitable for a video description.
        - Include a strong hook in the first sentence or two (visible before "Show more").
        - Optionally, add timestamps if describing specific content sections in a longer video.
        - Optimize for search with relevant keywords throughout the description.
        - Include a clear call to action (e.g., subscribe, watch another video, check links).
        ''';
        break;
    }

    // Base prompt with additional customization
    return '''
    Generate a social media post for the platform "$selectedPlatform" with the following characteristics:
    
    Topic: $topic
    Main message: $message
    Tone: $selectedTone
    Goal: $selectedGoal
    Desired Length: $selectedLength (interpret this relative to the platform norms, e.g., 'Long' for Twitter is still short)
    Keywords to include naturally within the text: ${keywords.isNotEmpty ? keywords : "None specified"}
    ${includeHashtags ? "Include relevant hashtags. ${hashtags.isNotEmpty ? "Prioritize these if relevant: $hashtags." : "Generate 3-5 highly relevant hashtags based on the topic and platform."}" : "Do not include any hashtags."}
    ${includeSeoKeywords ? "Consider including SEO keywords if appropriate for the platform (e.g., Pinterest, YouTube description)." : ""}
    Call to action: ${cta.isNotEmpty ? cta : "Include a relevant call to action suitable for $selectedPlatform and the $selectedGoal goal."}
    
    Platform-specific guidelines for $selectedPlatform:
    $platformSpecificPrompt
    
    Ensure the post follows typical formatting and best practices for $selectedPlatform.
    Generate only the post content itself, starting directly with the text. Do not include labels like "Post:", "Hashtags:", or any introductory/explanatory text before or after the post.
    ''';
  }

  // API service
  final GroqApiService _groqApiService = GroqApiService(
    apiKey: dotjsonenv.env['_groqApiKey'] ?? "",
  );

  @override
  void showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 4),
        action: SnackBarAction(
          label: 'OK',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }
}
