// ignore_for_file: deprecated_member_use, avoid_print, use_build_context_synchronously, library_private_types_in_public_api, depend_on_referenced_packages, file_names, overridden_fields
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sizer/sizer.dart';
import 'package:yoobble/models/tab_controller.dart'; // Added import
import '../../models/groq_API.dart';
import '../../models/quotas.dart';
import '../../stripe/paywall.dart';
import '../../stripe/stripeinfo.dart';
import '../../utils/responsive.dart';
import 'based_class.dart';

class SalesCopyGenerator extends BaseGenerator {
  const SalesCopyGenerator({
    super.key,
  });

  @override
  _SalesCopyGeneratorState createState() => _SalesCopyGeneratorState();
}

class _SalesCopyGeneratorState extends BaseGeneratorState<SalesCopyGenerator>
    with SingleTickerProviderStateMixin {
  final TextEditingController productController = TextEditingController();
  final TextEditingController targetAudienceController =
      TextEditingController();
  final TextEditingController valuePropositionController =
      TextEditingController();
  final TextEditingController painPointsController = TextEditingController();
  final TextEditingController featuresController = TextEditingController();
  final TextEditingController benefitsController = TextEditingController();
  final TextEditingController callToActionController = TextEditingController();
  final TextEditingController offerDetailsController = TextEditingController();

  // TabController for mobile view
  late TabController _tabController;

  String selectedCopyType = 'Landing Page';
  String selectedIndustry = 'Technology';
  String selectedTone = 'Persuasive';
  String selectedLength = 'Medium';
  String selectedStrategy = 'Problem-Solution';
  String? _errorMessage;

  final List<String> copyTypes = [
    'Landing Page',
    'Email Sequence',
    'Product Description',
    'Sales Letter',
    'Social Media Post',
    'Video Script',
    'Webinar Script'
  ];

  final List<String> industries = [
    'Technology',
    'Health & Wellness',
    'E-commerce',
    'Finance',
    'Education',
    'Real Estate',
    'SaaS',
    'Coaching',
    'Food & Beverage',
    'Fashion',
    'Travel',
    'Fitness'
  ];

  final List<String> tones = [
    'Persuasive',
    'Authoritative',
    'Conversational',
    'Urgent',
    'Enthusiastic',
    'Professional',
    'Emotional',
    'Direct'
  ];

  final List<String> lengths = ['Short', 'Medium', 'Long', 'Ultra Long'];

  final List<String> strategies = [
    'Problem-Solution',
    'Before-After-Bridge',
    'Feature-Benefit',
    'Social Proof',
    'Scarcity',
    'Story-Based',
    'Pain-Agitate-Solve',
    'AIDA'
  ];

  // Improved color scheme
  final Color primaryColor = Color.fromARGB(255, 0, 34, 108); // Blue
  final Color secondaryColor =
      Color.fromARGB(255, 1, 4, 14); // Darker blue (Used for Pro)
  final Color accentColor = Color(0xFF047857); // Green accent
  final Color backgroundColor = Color(0xFFF8FAFC); // Light slate
  final Color cardColor = Colors.white;
  final Color textColor = Color(0xFF1F2937); // Dark gray
  final Color lightTextColor = Color(0xFF6B7280); // Medium gray
  final Color errorColor = Color(0xFFDC2626); // Error red (Consistent)

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
  int _dailyLimit = ApiQuotaManager.dailyLimit; // Default limit for free users
  bool _isLoadingQuota = true;
  bool _hasUnlimitedQuota =
      false; // Flag for unlimited quota (Standard/Business)
  // --- End Quota Variables ---

  @override
  void initState() {
    super.initState();
    // Initialize TabController for mobile view
    _tabController = TabController(length: 2, vsync: this);
    // Load subscription status (this will trigger quota/limit refresh)
    _checkUserSubscription();
    // Initial load (will be overwritten after subscription check)
    _loadRemainingQuota();
    _loadCurrentDailyLimit();
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
        // Determine unlimited status
        _hasUnlimitedQuota = remaining == -1 ||
            (userSubscriptionPlan == 'Standard' ||
                userSubscriptionPlan == 'Business');
        _isLoadingQuota = false;
      });
    } catch (e) {
      setState(() {
        _remainingQuota = 0;
        _hasUnlimitedQuota = false;
        _isLoadingQuota = false;
      });
      print('Error loading quota: $e');
    }
  }

  Future<void> _loadCurrentDailyLimit() async {
    try {
      final limit = await _quotaManager.getCurrentDailyLimit();
      setState(() {
        _dailyLimit = limit;
      });
    } catch (e) {
      print('Error loading daily limit: $e');
      if (mounted) {
        setState(() {
          // Fallback based on known plan if manager fails
          if (userSubscriptionPlan == 'Pro') {
            _dailyLimit = ApiQuotaManager.proDailyLimit;
          } else {
            _dailyLimit = ApiQuotaManager.dailyLimit;
          }
        });
      }
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
    // No need to set loading here, _checkUserSubscription does it.
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
          // Refresh quota/limit for the 'null' plan state
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
            // Explicitly set plan to null if no active subs found
            fetchedPlan = null;
            wasSubscribed = false;
            wasTrial = false;
          }
        } else {
          print('Stripe response format unexpected: ${response.body}');
        }
      } else if (response.statusCode == 404) {
        print(
            "Customer $customerId not found on Stripe or has no subscriptions.");
        fetchedPlan = null; // No plan if customer not found
        wasSubscribed = false;
        wasTrial = false;
      } else {
        print(
            'Stripe API error fetching subscriptions: ${response.statusCode} ${response.body}');
        // Keep previous state on API error? Or assume not subscribed? Safer to assume not.
        fetchedPlan = null;
        wasSubscribed = false;
        wasTrial = false;
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

        // Refresh quota and limit *after* subscription plan is determined
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
        // Refresh quota/limit for the error state (likely free tier)
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
    // _checkSubscriptionStatus will fetch the plan name, update state, and then refresh quota/limit
    await _checkSubscriptionStatus();
    // No need for else block setting state here, _checkSubscriptionStatus handles the null customerId case.
  }

  // Getter for remaining trial days
  String get _getRemainingTrialDays {
    if (!_isTrialActive || _trialEndDate == null) return "0";
    final difference = _trialEndDate!.difference(DateTime.now());
    // Return 0 if difference is negative or zero
    return difference.inDays > 0 ? difference.inDays.toString() : "0";
  }
  // --- End Subscription Check Methods ---

  @override
  void dispose() {
    productController.dispose();
    targetAudienceController.dispose();
    valuePropositionController.dispose();
    painPointsController.dispose();
    featuresController.dispose();
    benefitsController.dispose();
    callToActionController.dispose();
    offerDetailsController.dispose();
    _tabController.dispose(); // Dispose TabController
    super.dispose(); // Calls dispose on BaseGeneratorState
  }

  // --- Upgrade Dialog and Navigation (Using Consistent Structure) ---
  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          // Use AlertDialog for consistency
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20), // Consistent border radius
          ),
          contentPadding: EdgeInsets.zero, // Remove default padding
          content: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20), // Match shape
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
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
                        'Upgrade Required', // Consistent title
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Courier', // Match style if desired
                        ),
                      ),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Conditional Trial Info
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
                                    fontFamily: 'Courier', // Match style
                                    color: Colors.amber[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Conditional Pro Limit Info
                      else if (userSubscriptionPlan == 'Pro')
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: secondaryColor
                                .withOpacity(0.1), // Use Pro color (secondary)
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color:
                                    secondaryColor), // Use Pro color (secondary)
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star,
                                  color:
                                      secondaryColor), // Pro icon with Pro color
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.',
                                  style: TextStyle(
                                    fontFamily: 'Courier', // Match style
                                    color:
                                        secondaryColor, // Use Pro color (secondary)
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      // Default Message for Free Users
                      else
                        Text(
                          'This feature requires an active subscription or available quota.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontFamily: 'Courier', // Match style
                          ),
                        ),
                      SizedBox(height: 24),
                      // Action Buttons
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
                                fontFamily: 'Courier', // Match style
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
                                borderRadius: BorderRadius.circular(
                                    30), // Consistent button shape
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
                                    fontFamily: 'Courier', // Match style
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
          shape: RoundedRectangleBorder(
            // Consistent shape
            borderRadius: BorderRadius.circular(16),
          ),
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
    await _checkSubscriptionStatus(); // This updates _isSubscribed and plan

    // Close the loading dialog
    if (Navigator.of(context, rootNavigator: true).canPop()) {
      Navigator.of(context, rootNavigator: true).pop();
    }

    // Navigate based on the updated status
    if (!context.mounted) return; // Check context validity after async gap

    // Use _isSubscribed OR _isTrialActive to determine navigation
    if (_isSubscribed || _isTrialActive) {
      // Navigate to info page if subscribed (active or trial)
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionInfoPage(),
        ),
      );
    } else {
      // Navigate to paywall if not subscribed and trial ended/inactive
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionBottomSheet(),
        ),
      );
    }
  }
  // --- End Upgrade Dialog and Navigation ---

  // --- Helper to build Status Chip (Adapted Logic) ---
  Widget _buildStatusChip() {
    // Loading state
    if (_isSubscriptionLoading || _isLoadingQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: Text("..."), // More subtle loading
          ),
        ),
      );
    }

    // Standard and Business Plans (Unlimited Quota)
    if (userSubscriptionPlan != null &&
        (userSubscriptionPlan == 'Standard' ||
            userSubscriptionPlan == 'Business')) {
      Color chipColor = Colors.grey[200]!;
      Color textColor = Colors.black87;
      IconData icon = Icons.check_circle_outline;

      switch (userSubscriptionPlan) {
        case 'Standard':
          chipColor = Colors.blue[100]!;
          textColor = Colors.blue[800]!;
          icon = Icons.star_border;
          break;
        case 'Business':
          chipColor = Colors.green[100]!;
          textColor = Colors.green[800]!;
          icon = Icons.business;
          break;
      }

      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            avatar: Icon(icon, size: 16, color: textColor),
            label: Text(
              '$userSubscriptionPlan Plan',
              style: TextStyle(
                  color: textColor, fontWeight: FontWeight.bold, fontSize: 11),
            ),
            backgroundColor: chipColor,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Pro Plan (Specific Limit)
    if (userSubscriptionPlan == 'Pro') {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            avatar: Icon(Icons.star,
                size: 16,
                color:
                    secondaryColor), // Pro icon and color (Using secondaryColor for Pro)
            label: Text(
              'Pro $_remainingQuota/${ApiQuotaManager.proDailyLimit}', // Show Pro limit
              style: TextStyle(
                color: secondaryColor, // Use secondaryColor for Pro text
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            backgroundColor: secondaryColor.withOpacity(0.2), // Pro color
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Free Users (Default Limit, showing quota)
    if (!_hasUnlimitedQuota) {
      // This covers free users
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            label: Text(
              '$_remainingQuota/$_dailyLimit', // Use the potentially dynamic _dailyLimit
              style: TextStyle(
                color: _remainingQuota < 5 ? Colors.white : textColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            avatar: Icon(
              // Add an icon for free tier quota
              Icons.hourglass_empty,
              size: 14,
              color: _remainingQuota < 5 ? Colors.white : textColor,
            ),
            backgroundColor: _remainingQuota == 0 // Show red clearly when 0
                ? errorColor // Use errorColor
                : (_remainingQuota < 5 ? Colors.orange : Colors.grey[200]),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.only(
                left: 2.0, right: 4.0), // Adjust padding for icon
          ),
        ),
      );
    }

    // Fallback/Unknown State (Should ideally not be reached often)
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
      // User profile avatar and menu can be added here if needed
    ];

    return ResponsiveWidget(
      // --- Mobile View ---
      mobile: Scaffold(
        backgroundColor: Colors.white, // Keep original background
        appBar: AppBar(
          backgroundColor: cardColor,
          surfaceTintColor: cardColor,
          automaticallyImplyLeading: false,
          elevation: 0,
          shadowColor: Colors.grey.withOpacity(0.1),
          title: Text(
            "Sales Copy", // Keep original title
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 18, // Consistent mobile title size
            ),
          ),
          centerTitle: false,
          iconTheme: IconThemeData(color: textColor),
          actions: appBarActions,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Create'),
              Tab(text: 'Preview'),
            ],
            labelColor: primaryColor, // Use generator's primary color
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: primaryColor, // Use generator's primary color
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Form/Options
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Card(
                  // Wrap form in a Card
                  color: cardColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child:
                        buildForm(), // Call buildForm which contains the form content
                  ),
                ),
              ),

              // Tab 2: Generated Content Results
              SingleChildScrollView(
                padding: EdgeInsets.all(16.0),
                child: Card(
                  // Wrap results in a Card
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Container(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      // Use Column for results content
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header with title and actions (Mobile Style)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    FontAwesomeIcons.moneyCheckDollar,
                                    color: primaryColor,
                                    size: 16,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Generated Copy',
                                  style: TextStyle(
                                    fontSize: 16, // Adjusted size
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              // Mobile action buttons
                              children: [
                                _buildActionButton(
                                    isActive: isEditing,
                                    activeIcon: Icons.check,
                                    inactiveIcon: Icons.edit,
                                    onPressed: () => setState(() {
                                          isEditing = !isEditing;
                                        }),
                                    tooltip: isEditing ? 'Done' : 'Edit',
                                    activeColor: primaryColor),
                                SizedBox(width: 4),
                                _buildActionButton(
                                    isActive: isCopied,
                                    activeIcon: Icons.check,
                                    inactiveIcon: Icons.copy,
                                    onPressed: () {
                                      /* copy logic */ if (generatedContent
                                          .isNotEmpty)
                                        copyToClipboard(isEditing
                                            ? generatedContentController.text
                                            : generatedContent);
                                    },
                                    tooltip: isCopied ? 'Copied' : 'Copy',
                                    activeColor: Colors.green),
                                SizedBox(width: 4),
                                _buildActionButton(
                                    isActive: isSaved,
                                    activeIcon: Icons.check,
                                    inactiveIcon: Icons.save_outlined,
                                    onPressed: saveContent,
                                    tooltip: isSaved ? 'Saved' : 'Save',
                                    activeColor: Colors.green),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 16),
                        // Preview/edit area (Mobile Style)
                        Container(
                          height: 60.h, // Set height for scrollable area
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          padding: EdgeInsets.all(16),
                          child: isEditing
                              ? TextField(
                                  /* TextField setup */ controller:
                                      generatedContentController,
                                  maxLines: null,
                                  expands: true,
                                  textAlignVertical: TextAlignVertical.top,
                                  decoration: InputDecoration.collapsed(
                                      hintText: '...'),
                                  style: TextStyle(
                                      fontSize: 14,
                                      height: 1.5,
                                      color: textColor))
                              : isGenerating
                                  ? Center(
                                      child: Column(
                                          /* Loading */ mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                          CircularProgressIndicator(
                                            color: primaryColor,
                                            strokeWidth: 2,
                                          ),
                                          SizedBox(height: 16),
                                          Text('Creating persuasive copy...',
                                              style: TextStyle(
                                                  color: primaryColor,
                                                  fontWeight: FontWeight.w500))
                                        ]))
                                  : SingleChildScrollView(
                                      child: generatedContent.isEmpty
                                          ? Center(
                                              child: Padding(
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 50.0),
                                                  child: Text(
                                                      'Sales copy appears here',
                                                      style: TextStyle(
                                                          color: Colors
                                                              .grey[400]))))
                                          : Text(generatedContent,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  height: 1.5,
                                                  color: textColor)),
                                    ),
                        ),
                        // Badges (Mobile Style)
                        if (generatedContent.isNotEmpty && !isGenerating)
                          Container(
                            margin: EdgeInsets.only(top: 16),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(selectedCopyType,
                                    FontAwesomeIcons.fileLines, primaryColor),
                                _buildBadge(selectedStrategy,
                                    FontAwesomeIcons.chartLine, accentColor),
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
      ),

      // --- Desktop View ---
      desktop: Scaffold(
        backgroundColor: Colors.white, // Keep original background
        appBar: AppBar(
          shadowColor: Colors.transparent,
          automaticallyImplyLeading: false,
          elevation: 0,
          surfaceTintColor: Colors.white,
          backgroundColor: Colors.white,
          actions: appBarActions,
        ),
        body: Padding(
          // Added padding around the Row for desktop
          padding: EdgeInsets.all(1.5.w),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left side - Form
              SizedBox(
                width: 35.w, // Keep width constraint
                child: Card(
                  color: cardColor,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    // Call buildForm which now contains the form structure
                    child: buildForm(),
                  ),
                ),
              ),

              SizedBox(width: 2.w), // Keep original spacing

              // Right side - Generated content
              Expanded(
                child: Card(
                  elevation: 0,
                  color: cardColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      // Use Column for results content
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header with title and actions (Desktop Style)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    FontAwesomeIcons.moneyCheckDollar,
                                    color: primaryColor,
                                    size: 20,
                                  ),
                                ),
                                SizedBox(width: 16),
                                Text(
                                  'Generated Sales Copy',
                                  style: TextStyle(
                                    fontSize: 18, // Larger for desktop
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              // Desktop action buttons
                              children: [
                                _buildDesktopActionButton(
                                    isActive: isEditing,
                                    label: isEditing ? 'Done' : 'Edit',
                                    icon: isEditing ? Icons.check : Icons.edit,
                                    onPressed: () => setState(() {
                                          isEditing = !isEditing;
                                        }),
                                    activeColor: primaryColor),
                                SizedBox(width: 8),
                                _buildDesktopActionButton(
                                    isActive: isCopied,
                                    label: isCopied ? 'Copied' : 'Copy',
                                    icon: isCopied ? Icons.check : Icons.copy,
                                    onPressed: () {
                                      /* copy logic */ if (generatedContent
                                          .isNotEmpty)
                                        copyToClipboard(isEditing
                                            ? generatedContentController.text
                                            : generatedContent);
                                    },
                                    activeColor: Colors.green),
                                SizedBox(width: 8),
                                _buildDesktopActionButton(
                                    isActive: isSaved,
                                    label: isSaved ? 'Saved' : 'Save',
                                    icon: isSaved ? Icons.check : Icons.save,
                                    onPressed: saveContent,
                                    activeColor: Colors.green),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 24),

                        // Preview/edit area (Desktop Style)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            padding: EdgeInsets.all(24),
                            child: isEditing
                                ? TextField(
                                    /* TextField setup */ controller:
                                        generatedContentController,
                                    maxLines: null,
                                    expands: true,
                                    textAlignVertical: TextAlignVertical.top,
                                    decoration: InputDecoration.collapsed(
                                        hintText: '...'),
                                    style: TextStyle(
                                        fontSize: 16,
                                        height: 1.6,
                                        color: textColor))
                                : isGenerating
                                    ? Center(
                                        child: Column(
                                            /* Loading Column */ mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                            CircularProgressIndicator(
                                              color: primaryColor,
                                              strokeWidth: 3,
                                            ),
                                            SizedBox(height: 24),
                                            Text('Creating persuasive copy...',
                                                style: TextStyle(
                                                    color: primaryColor,
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                            SizedBox(height: 8),
                                            Text('This may take a moment',
                                                style: TextStyle(
                                                    color: lightTextColor,
                                                    fontSize: 14))
                                          ]))
                                    : SingleChildScrollView(
                                        child: generatedContent.isEmpty
                                            ? Center(
                                                child: Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            vertical: 50.0),
                                                    child: Column(
                                                        /* Empty State Column */ mainAxisAlignment:
                                                            MainAxisAlignment
                                                                .center,
                                                        children: [
                                                          Icon(
                                                              FontAwesomeIcons
                                                                  .fileLines,
                                                              size: 48,
                                                              color: Colors
                                                                  .grey[300]),
                                                          SizedBox(height: 24),
                                                          Text(
                                                              'Sales copy appears here',
                                                              style: TextStyle(
                                                                  fontSize: 18,
                                                                  color: Colors
                                                                          .grey[
                                                                      400],
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500)),
                                                          SizedBox(height: 12),
                                                          Text(
                                                              'Fill form & click Generate',
                                                              style: TextStyle(
                                                                  fontSize: 14,
                                                                  color: Colors
                                                                          .grey[
                                                                      400]),
                                                              textAlign:
                                                                  TextAlign
                                                                      .center)
                                                        ])))
                                            : Text(generatedContent,
                                                style: TextStyle(
                                                    fontSize: 16,
                                                    height: 1.6,
                                                    color: textColor)),
                                      ),
                          ),
                        ),

                        // Badges (Desktop Style)
                        if (generatedContent.isNotEmpty && !isGenerating)
                          Container(
                            margin: EdgeInsets.only(top: 20),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(selectedCopyType,
                                    FontAwesomeIcons.fileLines, primaryColor),
                                _buildBadge(
                                    selectedIndustry,
                                    FontAwesomeIcons.briefcase,
                                    secondaryColor != Colors.black
                                        ? secondaryColor
                                        : primaryColor.withOpacity(0.7)),
                                _buildBadge(selectedTone,
                                    FontAwesomeIcons.commentDots, accentColor),
                                _buildBadge(
                                    selectedLength,
                                    FontAwesomeIcons.rulerHorizontal,
                                    Color(0xFF10B981)), // Emerald green
                                _buildBadge(
                                    selectedStrategy,
                                    FontAwesomeIcons.chartLine,
                                    Color(0xFFEF4444)), // Red
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
      ),
    );
  }

  // Mobile Dropdown Section (Keep original)
  Widget _buildMobileDropdownSection() {
    return Column(
      children: [
        buildDropdown(
          label: 'Copy Type',
          value: selectedCopyType,
          items: copyTypes,
          onChanged: (value) {
            setState(() {
              selectedCopyType = value!;
            });
          },
          icon: FontAwesomeIcons.fileLines,
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Industry',
          value: selectedIndustry,
          items: industries,
          onChanged: (value) {
            setState(() {
              selectedIndustry = value!;
            });
          },
          icon: FontAwesomeIcons.briefcase,
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Tone',
          value: selectedTone,
          items: tones,
          onChanged: (value) {
            setState(() {
              selectedTone = value!;
            });
          },
          icon: FontAwesomeIcons.faceLaughBeam,
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Length',
          value: selectedLength,
          items: lengths,
          onChanged: (value) {
            setState(() {
              selectedLength = value!;
            });
          },
          icon: FontAwesomeIcons.rulerHorizontal,
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Sales Strategy',
          value: selectedStrategy,
          items: strategies,
          onChanged: (value) {
            setState(() {
              selectedStrategy = value!;
            });
          },
          icon: FontAwesomeIcons.chartLine,
        ),
      ],
    );
  }

  // Desktop Dropdown Section (Keep original)
  Widget _buildDesktopDropdownSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: buildDropdown(
                label: 'Copy Type',
                value: selectedCopyType,
                items: copyTypes,
                onChanged: (value) {
                  setState(() {
                    selectedCopyType = value!;
                  });
                },
                icon: FontAwesomeIcons.fileLines,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Industry',
                value: selectedIndustry,
                items: industries,
                onChanged: (value) {
                  setState(() {
                    selectedIndustry = value!;
                  });
                },
                icon: FontAwesomeIcons.briefcase,
              ),
            ),
          ],
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
                icon: FontAwesomeIcons.faceLaughBeam,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Length',
                value: selectedLength,
                items: lengths,
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
        // Make Strategy dropdown full width on desktop as well
        buildDropdown(
          label: 'Sales Strategy / Framework',
          value: selectedStrategy,
          items: strategies,
          onChanged: (value) {
            setState(() {
              selectedStrategy = value!;
            });
          },
          icon: FontAwesomeIcons.chartLine,
        ),
      ],
    );
  }

  // Mobile Content Section (Keep original)
  Widget _buildMobileContentSection() {
    return Column(
      children: [
        buildTextField(
          controller: productController,
          label: 'Product or Service',
          hint: 'What are you selling?',
          icon: FontAwesomeIcons.box,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: targetAudienceController,
          label: 'Target Audience',
          hint: 'Who are your ideal customers?',
          icon: FontAwesomeIcons.userGroup,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: valuePropositionController,
          label: 'Value Proposition',
          hint: 'What makes your offer unique?',
          icon: FontAwesomeIcons.star,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: painPointsController,
          label: 'Customer Pain Points',
          hint: 'Problems your customers are facing',
          icon: FontAwesomeIcons.bandAid,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: featuresController,
          label: 'Key Features (optional)',
          hint: 'Main features of your product',
          icon: FontAwesomeIcons.list,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: benefitsController,
          label: 'Key Benefits (optional)',
          hint: 'How customers benefit',
          icon: FontAwesomeIcons.thumbsUp,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: offerDetailsController,
          label: 'Offer Details (optional)',
          hint: 'Pricing, bonuses, guarantees, etc.',
          icon: FontAwesomeIcons.tag,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: callToActionController,
          label: 'Call to Action',
          hint: 'What should the reader do next?',
          icon: FontAwesomeIcons.handPointer,
          required: true,
        ),
      ],
    );
  }

  // Desktop Content Section (Keep original)
  Widget _buildDesktopContentSection() {
    return Column(
      children: [
        buildTextField(
          controller: productController,
          label: 'Product or Service',
          hint: 'What are you selling?',
          icon: FontAwesomeIcons.box,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: targetAudienceController,
          label: 'Target Audience',
          hint: 'Who are your ideal customers?',
          icon: FontAwesomeIcons.userGroup,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: valuePropositionController,
          label: 'Value Proposition',
          hint: 'What makes your offer unique?',
          icon: FontAwesomeIcons.star,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: painPointsController,
          label: 'Customer Pain Points',
          hint: 'Problems your customers are facing',
          icon: FontAwesomeIcons.bandAid,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        Row(
          // Keep Features and Benefits side-by-side on desktop
          children: [
            Expanded(
              child: buildTextField(
                controller: featuresController,
                label: 'Key Features (optional)',
                hint: 'Main features of your product',
                icon: FontAwesomeIcons.list,
                maxLines: 2,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildTextField(
                controller: benefitsController,
                label: 'Key Benefits (optional)',
                hint: 'How customers benefit',
                icon: FontAwesomeIcons.thumbsUp,
                maxLines: 2,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: offerDetailsController,
          label: 'Offer Details (optional)',
          hint: 'Pricing, bonuses, guarantees, etc.',
          icon: FontAwesomeIcons.tag,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: callToActionController,
          label: 'Call to Action',
          hint: 'What should the reader do next?',
          icon: FontAwesomeIcons.handPointer,
          required: true,
        ),
      ],
    );
  }

  // Error Message Widget (Keep original, ensure errorColor is used)
  Widget _buildErrorMessage() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errorColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: errorColor, size: 20),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(
                  color: errorColor, fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // Quota Warning Widget (Adapted for consistency)
  Widget _buildQuotaWarning() {
    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: errorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: errorColor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2.0),
            child: Icon(Icons.warning, color: errorColor, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Limit Reached',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: errorColor,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  // *** Conditional Text for Pro vs Free ***
                  userSubscriptionPlan == 'Pro'
                      ? 'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.'
                      : 'You\'ve reached your daily free limit of $_dailyLimit generations. Upgrade to a paid plan for increased or unlimited access.',
                  style: TextStyle(
                    color: errorColor.withOpacity(0.9),
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 10),
                TextButton(
                  onPressed: _showUpgradeDialog,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    backgroundColor: errorColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(userSubscriptionPlan == 'Pro'
                      ? 'Upgrade Plan'
                      : 'Upgrade Now'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Generate Button Widget (Keep original)
  Widget _buildGenerateButton() {
    bool isDisabled =
        isGenerating || (_remainingQuota == 0 && !_hasUnlimitedQuota);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed:
            isDisabled ? null : generateContent, // Use combined condition
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          disabledBackgroundColor: primaryColor.withOpacity(0.6),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isGenerating
            ? SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    FontAwesomeIcons.wandMagicSparkles,
                    size: 18,
                    color: Colors.white,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generate Copy',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // Mobile Action Button (Keep original)
  Widget _buildActionButton({
    required bool isActive,
    required IconData activeIcon,
    required IconData inactiveIcon,
    required VoidCallback onPressed,
    required String tooltip,
    Color activeColor = Colors.blue, // Default, overridden below
    Color inactiveColor = const Color(0xFF6B7280), // Default lightTextColor
  }) {
    // Override activeColor based on the action if needed, e.g., green for copy/save
    if ((tooltip == 'Copied' || tooltip == 'Saved') && isActive) {
      activeColor = Colors.green;
    } else if (tooltip == 'Edit' && isActive) {
      activeColor = primaryColor; // Use primary color for active edit
    }
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(
          isActive ? activeIcon : inactiveIcon,
          color: isActive ? activeColor : inactiveColor,
          size: 20,
        ),
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor:
              isActive ? activeColor.withOpacity(0.1) : Colors.transparent,
          padding: EdgeInsets.all(8), // Consistent padding
          minimumSize: Size(40, 40), // Ensure minimum tap target size
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  // Desktop Action Button (Keep original)
  Widget _buildDesktopActionButton({
    required bool isActive,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required Color activeColor,
    Color inactiveColor = const Color(0xFF6B7280), // Default lightTextColor
  }) {
    return MouseRegion(
      // Add hover effect
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: AnimatedContainer(
          duration: Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? activeColor.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? activeColor.withOpacity(0.5)
                  : Colors.transparent, // Subtle border when active
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isActive ? activeColor : inactiveColor,
                size: 18,
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeColor : inactiveColor,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13, // Slightly smaller font for desktop button
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to create a badge (Keep original)
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

  @override
  Widget buildSectionHeader(String title, IconData icon) {
    // Keep original implementation
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: primaryColor, size: 16),
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
    // Keep original implementation
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
            if (required) SizedBox(width: 4),
            if (required)
              Text(
                '*',
                style: TextStyle(
                  color: errorColor, // Use defined errorColor
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
            textAlignVertical:
                maxLines > 1 ? TextAlignVertical.top : TextAlignVertical.center,
            style: TextStyle(fontSize: 15, color: textColor),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical:
                      maxLines > 1 ? 16 : 12), // Adjust padding for multi-line
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              prefixIcon: Padding(
                padding: EdgeInsets.only(
                    left: 12,
                    right: 8,
                    top: maxLines > 1
                        ? 12
                        : 0), // Adjust icon padding for multi-line
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 18,
                ),
              ),
              border: InputBorder.none,
              alignLabelWithHint: true,
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
    // Keep original implementation
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
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
          padding: EdgeInsets.only(left: 16, right: 12), // Adjust padding
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon:
                  Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
              style: TextStyle(
                color: textColor,
                fontSize: 14, // Consistent font size
                fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
              ),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              selectedItemBuilder: (BuildContext context) {
                return items.map<Widget>((String item) {
                  return Row(
                    children: [
                      Icon(icon, color: primaryColor, size: 18),
                      SizedBox(width: 12),
                      Flexible(
                        // Prevent overflow
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
                  child: Text(item),
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
    // Keep original implementation
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() {
      isCopied = true;
    });
    Future.delayed(Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          isCopied = false;
        });
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Content copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.green[700],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
      ),
    );
  }

  @override
  void generateContent() async {
    setState(() {
      _errorMessage = null; // Clear previous errors
      isGenerating = true; // Set generating true immediately
      generatedContent = ''; // Clear previous content
      isCopied = false; // Reset button states
      isSaved = false;
      isEditing = false;
    });

    // Basic validation (Keep original)
    if (productController.text.trim().isEmpty ||
        targetAudienceController.text.trim().isEmpty ||
        valuePropositionController.text.trim().isEmpty ||
        painPointsController.text.trim().isEmpty ||
        callToActionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all required fields (marked with *)';
        isGenerating = false; // Stop generation
      });
      showErrorSnackBar('Please fill in all required fields (marked with *)');
      return;
    }

    // *** UPDATED QUOTA CHECK ***
    final canMakeRequest = await _quotaManager.canMakeApiRequest();
    if (!canMakeRequest && !_hasUnlimitedQuota) {
      // Check requires quota AND is not unlimited
      setState(() {
        _errorMessage = userSubscriptionPlan == 'Pro'
            ? "You've reached your Pro plan daily limit. Upgrade to Standard or Business for unlimited access."
            : "You've reached your daily free limit. Upgrade to continue.";
        isGenerating = false; // Stop generation
      });
      _showUpgradeDialog(); // Show upgrade dialog with appropriate message
      return;
    }
    // *** END UPDATED QUOTA CHECK ***

    try {
      final prompt = _buildAIPrompt(); // Keep original prompt building
      final response = await _groqApiService.generateContent(prompt);

      // Record API usage only for users with limited quota (Free or Pro)
      if (!_hasUnlimitedQuota) {
        // Check the flag
        await _quotaManager.recordApiUsage();
        await _loadRemainingQuota(); // Refresh quota count in UI
      }

      if (mounted) {
        setState(() {
          generatedContent = response.trim(); // Trim whitespace
          generatedContentController.text = response.trim();
          isGenerating = false; // Generation finished
        });
        // Switch to results tab on mobile using the TabControllerMixin helper
        _tabController.navigateToResultsTabIfMobile(context);
      }
    } catch (e) {
      print('Error during API call: $e');
      if (mounted) {
        setState(() {
          isGenerating = false; // Stop generation on error
          _errorMessage = 'Failed to generate content. Please try again later.';
        });
        showErrorSnackBar('Error during generation. Please try again later.');
      }
    }
  }

  // Build the prompt for the AI API (Keep original)
  String _buildAIPrompt() {
    final String product = productController.text;
    final String audience = targetAudienceController.text;
    final String valueProposition = valuePropositionController.text;
    final String painPoints = painPointsController.text;
    final String features = featuresController.text;
    final String benefits = benefitsController.text;
    final String offerDetails = offerDetailsController.text;
    final String cta = callToActionController.text;

    // Construct a more detailed and structured prompt
    return '''
Act as an expert direct response copywriter specializing in high-converting sales copy. Generate persuasive copy based on the specified parameters.

**Sales Copy Type:** $selectedCopyType
**Industry:** $selectedIndustry
**Persuasion Framework:** $selectedStrategy
**Desired Tone:** $selectedTone
**Copy Length:** $selectedLength

**Core Information:**

*   **Product/Service:** $product
*   **Target Audience:** $audience (Consider their demographics, psychographics, and buying behavior)
*   **Value Proposition:** $valueProposition (The core promise your product delivers)
*   **Customer Pain Points:** $painPoints (Problems your solution addresses)
*   **Key Features:** ${features.isNotEmpty ? features : "Identify the most important features based on the product description."}
*   **Key Benefits:** ${benefits.isNotEmpty ? benefits : "Transform features into compelling benefits that address customer problems."}
*   **Offer Details:** ${offerDetails.isNotEmpty ? offerDetails : "Create appropriate pricing, guarantees, and bonuses if not specified."}
*   **Call to Action (CTA):** $cta

**Instructions:**

1.  **Framework Application:** Structure the copy rigorously following the **$selectedStrategy** framework (e.g., for AIDA: Attention, Interest, Desire, Action). Ensure each section logically leads to the next.
2.  **Length Adherence:** Craft copy that fits the **$selectedLength** requirement. Short: Concise and impactful. Medium: Balanced detail. Long/Ultra Long: Comprehensive, addressing all angles, overcoming objections.
3.  **Tone and Audience Resonance:** Write in the specified **$selectedTone** that connects with the **$audience** within the **$selectedIndustry**. Use their language.
4.  **Headline/Hook:** Start with a powerful headline or opening that grabs attention by highlighting the core **Pain Points** or the ultimate **Benefit/Desire**.
5.  **Persuasive Elements:** Incorporate elements like:
    *   Storytelling or relatable scenarios.
    *   Social proof (testimonials, case studies - mention where they would go).
    *   Addressing and overcoming potential objections.
    *   Creating urgency or scarcity (if applicable to the offer).
    *   Clearly articulating the **Value Proposition**.
    *   Highlighting a strong guarantee (if part of the **Offer Details**).
6.  **Call to Action:** Integrate the primary **$cta** clearly and compellingly. Include secondary CTAs if appropriate for longer copy.
7.  **Formatting:** Use Markdown for readability (headings, paragraphs, lists) suitable for the **$selectedCopyType**.

**Output:**
Provide ONLY the final, ready-to-use sales copy based on these instructions. Do not include any introductory text, section labels (unless part of the required format like email subject lines), or explanations.
''';
  }

  // Call to the Groq API (Keep original)
  final GroqApiService _groqApiService = GroqApiService(
    apiKey: dotjsonenv.env['_groqApiKey'] ?? "",
  );

  @override
  void showErrorSnackBar(String message) {
    // Ensure context is still valid before showing snackbar
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: errorColor, // Use defined errorColor
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss', // Consistent label
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  // buildForm implementation now returns the actual form content Column
  @override
  Widget buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Form header
        Container(
          padding: EdgeInsets.all(20), // Use consistent padding
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryColor.withOpacity(0.8),
                secondaryColor.withOpacity(0.8) // Use secondary color
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
                padding: EdgeInsets.all(12), // Use consistent padding
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FontAwesomeIcons.moneyCheckDollar, // Use Sales Copy icon
                  color: Colors.white,
                  size: 22, // Consistent size
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales Copy', // Consistent title
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18, // Consistent size
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Create high-converting copy that sells', // Consistent tagline
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

        // Style and format section
        buildSectionHeader('Copy Type & Strategy',
            FontAwesomeIcons.sliders), // Use consistent icon
        SizedBox(height: 20),
        // Use responsive helpers for dropdowns
        ResponsiveWidget(
          mobile: _buildMobileDropdownSection(),
          desktop: _buildDesktopDropdownSection(),
        ),
        SizedBox(height: 28),

        // Content details section
        buildSectionHeader('Copy Content Details',
            FontAwesomeIcons.penToSquare), // Use consistent icon
        SizedBox(height: 20),
        // Use responsive helpers for content fields
        ResponsiveWidget(
          mobile: _buildMobileContentSection(),
          desktop: _buildDesktopContentSection(),
        ),
        SizedBox(height: 28),

        // Error message if error
        if (_errorMessage != null) _buildErrorMessage(), // Use existing helper

        // *** START QUOTA DISPLAY LOGIC ***
        // Quota limit reached warning
        if (!_isLoadingQuota && !_hasUnlimitedQuota && _remainingQuota == 0)
          _buildQuotaWarning(), // Use consistent helper

        // Display quota remaining for users with limited quota (Free or Pro)
        if (!_isLoadingQuota &&
            !_hasUnlimitedQuota &&
            _remainingQuota > 0 &&
            (_remainingQuota < 5 || userSubscriptionPlan == 'Pro'))
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _remainingQuota < 5
                  ? Colors.amber.withOpacity(0.1)
                  : secondaryColor
                      .withOpacity(0.1), // Use Pro color base (secondary)
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _remainingQuota < 5
                    ? Colors.amber
                    : secondaryColor
                        .withOpacity(0.3), // Use Pro color base (secondary)
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: _remainingQuota < 5
                      ? Colors.amber[800]
                      : secondaryColor, // Use Pro color (secondary)
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    userSubscriptionPlan == 'Pro'
                        ? 'You have $_remainingQuota/${ApiQuotaManager.proDailyLimit} Pro generations remaining today.'
                        : 'You have $_remainingQuota/$_dailyLimit free generations remaining today.', // Use _dailyLimit for free users
                    style: TextStyle(
                      color: _remainingQuota < 5
                          ? Colors.amber[800]
                          : secondaryColor, // Use Pro color (secondary)
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // *** END QUOTA DISPLAY LOGIC ***

        // Generate button
        _buildGenerateButton(), // Use existing helper
      ],
    );
  }
}
