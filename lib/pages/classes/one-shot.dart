// ignore_for_file: unnecessary_brace_in_string_interps, deprecated_member_use, avoid_print, library_private_types_in_public_api, depend_on_referenced_packages, file_names, overridden_fields, use_build_context_synchronously
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:sizer/sizer.dart';
import 'package:yoobble/models/tab_controller.dart'; // Added import
import '../../models/groq_API.dart';
import '../../models/quotas.dart';
import '../../stripe/paywall.dart';
import '../../stripe/stripeinfo.dart';
import '../../utils/responsive.dart';
import 'based_class.dart';

class BlogPostGenerator extends BaseGenerator {
  const BlogPostGenerator({
    super.key,
  });

  @override
  _BlogPostGeneratorState createState() => _BlogPostGeneratorState();
}

class _BlogPostGeneratorState extends BaseGeneratorState<BlogPostGenerator>
    with SingleTickerProviderStateMixin {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController subjectController = TextEditingController();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController keywordsController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  // TabController for mobile view
  late TabController _tabController;

  String selectedTone = 'Professional';
  String selectedLanguage = 'English';
  String selectedRegion =
      'United States'; // Keep this if needed, though not in prompt
  String selectedAgeGroup =
      'Adults (25-45)'; // Keep this if needed, though not in prompt
  String selectedIndustry = 'Choose...';
  String selectedContentLength = 'Medium ';
  String selectedSEOLevel = 'Optimized';
  String selectedWritingStyle = 'Informative';
  bool includeImages = true; // Keep this if needed, though not in prompt
  bool includeCallToAction = true;
  bool includeSources = true;
  String? _errorMessage; // Added for displaying errors

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

  // Lists for tones and other dropdown items
  final List<String> tones = [
    'Professional',
    'Casual',
    'Friendly',
    'Formal',
    'Authoritative',
    'Conversational',
    'Educational',
    'Enthusiastic',
    'Humorous',
    'Inspirational'
  ];

  final List<String> languages = [
    'English',
    'Spanish',
    'French',
    'German',
    'Italian',
    'Portuguese',
    'Chinese',
    'Japanese',
    'Russian',
    'Arabic'
  ];

  // Color scheme
  final Color primaryColor = Color.fromARGB(255, 40, 25, 0); // Amber/gold
  final Color secondaryColor = Color.fromARGB(255, 16, 10, 0); // Amber/gold
  final Color accentColor = Color(0xFF8B5CF6); // Purple
  final Color backgroundColor = Color(0xFFF9FAFB); // Light gray
  final Color cardColor = Colors.white;
  final Color textColor = Color(0xFF1F2937); // Dark gray
  final Color lightTextColor = Color(0xFF6B7280); // Medium gray
  final Color errorColor = Color(0xFFDC2626); // Error red (Consistent)

  // Lists for this specific generator
  final List<String> industries = [
    'Choose...',
    'Technology',
    'Healthcare',
    'Finance',
    'Education',
    'Fashion',
    'Food',
    'Travel',
    'Real Estate',
    'Media',
    'Arts & Entertainment',
    'Sports',
    'Beauty',
    'Environment',
    'Automotive',
    'Retail',
    'Wellness',
    'B2B',
    'Manufacturing',
    'Other'
  ];

  final List<String> contentLengths = [
    'Short ',
    'Medium ',
    'Long ',
    'Very Long '
  ];

  final List<String> seoLevels = ['Basic', 'Optimized', 'Highly Optimized'];

  final List<String> writingStyles = [
    'Informative',
    'Narrative',
    'Descriptive',
    'Persuasive',
    'Analytical',
    'Technical',
    'Creative',
    'Journalistic',
    'Academic'
  ];

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
    titleController.dispose();
    subjectController.dispose();
    descriptionController.dispose();
    keywordsController.dispose();
    notesController.dispose();
    _tabController.dispose(); // Dispose TabController
    super.dispose();
  }

  // --- Upgrade Dialog and Navigation (Using Consistent Structure) ---
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
                        'Upgrade Required', // Consistent title
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          fontFamily: 'Courier', // Match style
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
                                    fontFamily: 'Courier', // Match style
                                    color: Colors.amber[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (userSubscriptionPlan ==
                          'Pro') // *** Pro Specific Message ***
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color:
                                accentColor.withOpacity(0.1), // Use Pro color
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: accentColor),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: accentColor), // Pro icon
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.',
                                  style: TextStyle(
                                    fontFamily: 'Courier', // Match style
                                    color: accentColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else // *** Standard message for free users ***
                        Text(
                          // Keep the original BlogPost message or make it generic
                          'This feature requires an active subscription or available quota.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black87,
                            fontFamily: 'Courier', // Match style
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
                size: 16, color: accentColor), // Pro icon and color
            label: Text(
              'Pro $_remainingQuota/${ApiQuotaManager.proDailyLimit}', // Show Pro limit
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            backgroundColor: accentColor.withOpacity(0.2), // Pro color
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
                ? Colors.red[700]
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
    ];

    return ResponsiveWidget(
      // --- Mobile View ---
      mobile: Scaffold(
        backgroundColor: Colors.white, // Keep original background
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: cardColor,
          surfaceTintColor: cardColor,
          elevation: 1,
          shadowColor: Colors.grey.withOpacity(0.1),
          title: Text(
            "One-Shot Blog Post", // Keep original title
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          centerTitle: false,
          iconTheme: IconThemeData(color: textColor),
          actions: appBarActions,
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Options'),
              Tab(text: 'Results'),
            ],
            labelColor: primaryColor, // Use primary color for selected tab
            unselectedLabelColor: Colors.grey[600], // Keep unselected color
            indicatorColor: primaryColor, // Match selected label color
            indicatorWeight: 3.0,
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
                    child: buildForm(),
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
                    // Removed fixed height to allow content to determine size
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min, // Adjust column size
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
                                    color: primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    FontAwesomeIcons.blog,
                                    color: primaryColor,
                                    size: 16,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Generated Blog Post',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                            // Action buttons (Keep original mobile style)
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
                        Container(
                          // Add a container to manage the text area height
                          height: 60.h, // Define a height or use constraints
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          padding: EdgeInsets.all(12),
                          child: isEditing
                              ? TextField(
                                  controller: generatedContentController,
                                  maxLines: null, // Allows unlimited lines
                                  expands: true, // Makes it fill the container
                                  textAlignVertical:
                                      TextAlignVertical.top, // Align text top
                                  decoration: InputDecoration.collapsed(
                                    hintText: 'Generated blog post text...',
                                    hintStyle: TextStyle(
                                        color: Colors.grey[400], fontSize: 14),
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
                                      // Make the read-only view scrollable
                                      child: generatedContent.isEmpty
                                          ? Center(
                                              child: Padding(
                                              // Add padding for empty state
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 50.0),
                                              child: Text(
                                                  'Blog post content appears here.',
                                                  style: TextStyle(
                                                      color: Colors.grey[400])),
                                            ))
                                          : Text(generatedContent,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  height: 1.5,
                                                  color: textColor)),
                                    ),
                        ),
                        // Badges (Keep original)
                        if (generatedContent.isNotEmpty && !isGenerating)
                          Container(
                            margin: EdgeInsets.only(top: 12),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _buildBadge(selectedWritingStyle,
                                    FontAwesomeIcons.pen, primaryColor),
                                _buildBadge(
                                    selectedContentLength,
                                    FontAwesomeIcons.textHeight,
                                    secondaryColor),
                                _buildBadge('SEO: $selectedSEOLevel',
                                    FontAwesomeIcons.searchengin, accentColor),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              )
            ],
          ),
        ),
      ),
      desktop: Scaffold(
        backgroundColor: Colors.white, // Keep original background
        appBar: AppBar(
          automaticallyImplyLeading: false,
          shadowColor: Colors.transparent,
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
              // Left side - Form (Keep original flex and structure)
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
                    // Keep ClipRRect for potential overflow clipping
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      // Removed fixed decoration/shadow from inner container, rely on Card
                      padding: const EdgeInsets.all(24.0),
                      child: SingleChildScrollView(
                        child: buildForm(),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(width: 2.w), // Keep original spacing

              // Right side - Generated content (Keep original flex and structure)
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
                        // Header of the right side (Keep original)
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
                                    FontAwesomeIcons.blog,
                                    color: primaryColor,
                                    size: 18,
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  'Generated Blog Post',
                                  style: TextStyle(
                                    fontSize: 18, // Slightly larger for desktop
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            // Action buttons (Using desktop style)
                            Row(
                              children: [
                                _buildDesktopActionButton(
                                  isActive: isEditing,
                                  label: isEditing ? 'Done' : 'Edit',
                                  icon: isEditing ? Icons.check : Icons.edit,
                                  onPressed: () {
                                    setState(() {
                                      isEditing = !isEditing;
                                    });
                                  },
                                  activeColor: primaryColor,
                                ),
                                SizedBox(width: 8),
                                _buildDesktopActionButton(
                                  isActive: isCopied,
                                  label: isCopied ? 'Copied' : 'Copy',
                                  icon: isCopied ? Icons.check : Icons.copy,
                                  onPressed: () {
                                    final textToCopy = isEditing
                                        ? generatedContentController.text
                                        : generatedContent;
                                    if (textToCopy.isNotEmpty) {
                                      copyToClipboard(textToCopy);
                                    }
                                  },
                                  activeColor: Colors.green,
                                ),
                                SizedBox(width: 8),
                                _buildDesktopActionButton(
                                  isActive: isSaved,
                                  label: isSaved ? 'Saved' : 'Save',
                                  icon: isSaved ? Icons.check : Icons.save,
                                  onPressed: saveContent,
                                  activeColor: Colors.green,
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 24),

                        // Preview/edit area (Keep original)
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
                                    textAlignVertical:
                                        TextAlignVertical.top, // Align text top
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText:
                                          'The generated blog post will appear here...',
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
                                              'Creating your blog post...',
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
                                        // Ensure read-only view is scrollable
                                        child: generatedContent.isEmpty
                                            ? Center(
                                                child: Padding(
                                                  // Add padding for empty state
                                                  padding: EdgeInsets.symmetric(
                                                      vertical: 50.0),
                                                  child: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    children: [
                                                      Icon(
                                                        FontAwesomeIcons
                                                            .penFancy,
                                                        size: 40,
                                                        color: Colors.grey[300],
                                                      ),
                                                      SizedBox(height: 24),
                                                      Text(
                                                        'Your blog post will appear here',
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          color:
                                                              Colors.grey[400],
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Text(
                                                        'Fill in the form and click "Generate Blog Post" to create your content',
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          color:
                                                              Colors.grey[400],
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
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

                        // Content badges (Keep original)
                        if (generatedContent.isNotEmpty && !isGenerating)
                          Container(
                            margin: EdgeInsets.only(top: 20),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildBadge(
                                  selectedWritingStyle,
                                  FontAwesomeIcons.pen,
                                  primaryColor,
                                ),
                                _buildBadge(
                                  selectedContentLength,
                                  FontAwesomeIcons.textHeight,
                                  secondaryColor,
                                ),
                                _buildBadge(
                                  'SEO: $selectedSEOLevel',
                                  FontAwesomeIcons.searchengin,
                                  accentColor,
                                ),
                                _buildBadge(
                                  selectedIndustry != 'Choose...'
                                      ? selectedIndustry
                                      : 'General',
                                  FontAwesomeIcons.industry,
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
      ),
    );
  }

  // Desktop Action Button Helper (Copied from AdsGenerator for consistency)
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
  Widget buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Form header (Keep original)
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                primaryColor.withOpacity(0.8),
                accentColor.withOpacity(0.8) // Use accent color in gradient
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
                  FontAwesomeIcons.blog,
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
                      'Create Engaging Blog Posts',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'SEO-optimized content to engage your audience',
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

        // Basic Information section (Keep original)
        buildSectionHeader('Basic Information',
            FontAwesomeIcons.fileLines), // Use fileLines icon
        SizedBox(height: 20),

        buildTextField(
          controller: titleController,
          label: 'Blog Post Title',
          hint: 'Enter an engaging title for your blog post',
          icon: Icons.title,
          required: true,
        ),
        SizedBox(height: 16),

        buildTextField(
          controller: subjectController,
          label: 'Main Subject',
          hint: 'What is the main topic of your blog post?',
          icon: Icons.subject,
          required: true,
        ),
        SizedBox(height: 16),

        buildTextField(
          controller: descriptionController,
          label: 'Detailed Description',
          hint: 'Describe in detail what you want to cover in this post...',
          icon: Icons.description,
          maxLines: 5,
          required: true,
        ),
        SizedBox(height: 16),

        buildTextField(
          controller: keywordsController,
          label: 'Keywords (separated by commas)',
          hint: 'SEO, digital marketing, strategy, ranking...',
          icon: Icons.vpn_key,
        ),
        SizedBox(height: 24),

        // Structure and Style section (Keep original)
        buildSectionHeader('Structure and Style',
            FontAwesomeIcons.penRuler), // Use penRuler icon
        SizedBox(height: 20),

        Row(
          children: [
            Expanded(
              child: buildDropdown(
                label: 'Content Length',
                value: selectedContentLength,
                items: contentLengths,
                onChanged: (value) {
                  setState(() {
                    selectedContentLength = value!;
                  });
                },
                icon: Icons.format_size,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Writing Style',
                value: selectedWritingStyle,
                items: writingStyles,
                onChanged: (value) {
                  setState(() {
                    selectedWritingStyle = value!;
                  });
                },
                icon: Icons.style,
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
                icon: Icons.record_voice_over,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'SEO Level',
                value: selectedSEOLevel,
                items: seoLevels,
                onChanged: (value) {
                  setState(() {
                    selectedSEOLevel = value!;
                  });
                },
                icon: Icons.search,
              ),
            ),
          ],
        ),
        SizedBox(height: 24),

        // Target Audience section (Keep original)
        buildSectionHeader('Target Audience', FontAwesomeIcons.users),
        SizedBox(height: 20),

        // Removed Region and Age Group as they were not in the final prompt
        buildDropdown(
          // Make Industry full width
          label: 'Industry / Sector',
          value: selectedIndustry,
          items: industries,
          onChanged: (value) {
            setState(() {
              selectedIndustry = value!;
            });
          },
          icon: Icons.business,
        ),
        SizedBox(height: 16),

        buildDropdown(
          // Make Language full width
          label: 'Language',
          value: selectedLanguage,
          items: languages,
          onChanged: (value) {
            setState(() {
              selectedLanguage = value!;
            });
          },
          icon: Icons.language,
        ),
        SizedBox(height: 24),

        // Additional Elements section (Keep original)
        buildSectionHeader('Additional Elements', FontAwesomeIcons.puzzlePiece),
        SizedBox(height: 20),

        Row(
          // Keep checkboxes side-by-side
          children: [
            Expanded(
              child: _buildCheckbox('Include Call to Action',
                  includeCallToAction, (val) => includeCallToAction = val!),
            ),
            Expanded(
              child: _buildCheckbox('Include Sources/Refs', includeSources,
                  (val) => includeSources = val!),
            ),
            // Removed Include Images checkbox as it wasn't in the final prompt
          ],
        ),
        SizedBox(height: 16),

        // Additional notes (Keep original)
        buildTextField(
          controller: notesController,
          label: 'Additional Notes or Instructions',
          hint: 'Any other instructions or preferences for your blog post?',
          icon: Icons.note_add,
          maxLines: 3,
        ),
        SizedBox(height: 28),

        // Warning message if error (Keep original)
        if (_errorMessage != null)
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: errorColor.withOpacity(0.1), // Use errorColor
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: errorColor.withOpacity(0.5)), // Use errorColor
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: errorColor), // Use errorColor
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                        color: errorColor, // Use errorColor
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),

        // *** START QUOTA DISPLAY LOGIC (Adapted from EmailGenerator/AdsGenerator) ***
        // Quota limit reached warning
        if (!_isLoadingQuota && !_hasUnlimitedQuota && _remainingQuota == 0)
          _buildQuotaWarning(), // Use new helper for consistency

        // Display quota remaining for users with limited quota (Free or Pro) - Added this section
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
                  : accentColor.withOpacity(0.1), // Use Pro color base
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _remainingQuota < 5
                    ? Colors.amber
                    : accentColor.withOpacity(0.3), // Use Pro color base
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: _remainingQuota < 5
                      ? Colors.amber[800]
                      : accentColor, // Use Pro color
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
                          : accentColor, // Use Pro color
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // *** END QUOTA DISPLAY LOGIC ***

        // Generate button (Keep original)
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            // Updated condition to check quota AND !unlimited
            onPressed:
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(FontAwesomeIcons.wandMagicSparkles,
                          color: Colors.white, size: 18),
                      SizedBox(width: 12),
                      Text(
                        'Generate Blog Post',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  // Helper for Checkboxes
  Widget _buildCheckbox(String title, bool value, Function(bool?) onChanged) {
    return CheckboxListTile(
      title: Text(title, style: TextStyle(fontSize: 13, color: textColor)),
      value: value,
      onChanged: (bool? newValue) {
        setState(() {
          onChanged(newValue);
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero, // Remove default padding
      dense: true, // Make it more compact
      activeColor: primaryColor,
    );
  }

  // Helper for Quota Warning (Similar to AdsGenerator)
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
            textAlignVertical:
                maxLines > 1 ? TextAlignVertical.top : TextAlignVertical.center,
            style: TextStyle(
              fontSize: 15,
              color: textColor,
            ),
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical:
                      maxLines > 1 ? 16 : 12), // Adjust padding for multi-line
              hintText: hint,
              hintStyle: TextStyle(
                color: Colors.grey[400],
                fontSize: 15,
              ),
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
              alignLabelWithHint: true, // Helps with multi-line hint alignment
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
          padding: EdgeInsets.only(left: 16, right: 12),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              icon:
                  Icon(Icons.keyboard_arrow_down_rounded, color: primaryColor),
              style: TextStyle(
                  color: textColor,
                  fontSize: 14, // Consistent font size
                  fontFamily:
                      Theme.of(context).textTheme.bodyLarge?.fontFamily),
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
    if (titleController.text.trim().isEmpty ||
        subjectController.text.trim().isEmpty ||
        descriptionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all required fields (*)';
        isGenerating = false; // Stop generation
      });
      showErrorSnackBar(
          'Please fill in at least the title, subject, and description');
      return;
    }
    if (selectedIndustry == 'Choose...') {
      setState(() {
        _errorMessage = 'Please select an Industry / Sector.';
        isGenerating = false; // Stop generation
      });
      showErrorSnackBar('Please select an Industry / Sector.');
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
          _errorMessage =
              'Failed to generate content. Error: ${e.toString()}'; // Show specific error
        });
        showErrorSnackBar('Error during generation: ${e.toString()}');
      }
    }
  }

  // Build the prompt for the AI API (Keep original, ensure variables match form)
  String _buildAIPrompt() {
    final String title = titleController.text;
    final String subject = subjectController.text;
    final String description = descriptionController.text;
    final String keywords = keywordsController.text;
    final String notes = notesController.text;
    final String industry = selectedIndustry != 'Choose...'
        ? selectedIndustry
        : 'General'; // Handle default case

    return '''
Generate a comprehensive and engaging blog post based on the following specifications:

**Core Content:**
*   **Title:** ${title}
*   **Main Subject:** ${subject}
*   **Detailed Description:** ${description}
*   **Keywords:** ${keywords.isNotEmpty ? keywords : "Determine relevant keywords based on the subject and description"}

**Style and Structure:**
*   **Content Length:** ${selectedContentLength} (Adjust depth and breadth accordingly)
*   **Writing Style:** ${selectedWritingStyle}
*   **Tone:** ${selectedTone}
*   **SEO Optimization Level:** ${selectedSEOLevel} (Incorporate keywords naturally, use headings, and structure for readability)

**Target Audience & Context:**
*   **Industry/Sector:** ${industry}
*   **Language:** ${selectedLanguage}
// Removed Region and Age Group from prompt as they were removed from the form

**Additional Elements to Include:**
${includeCallToAction ? "*   Include a relevant call to action towards the end." : "*   Do not include a specific call to action."}
${includeSources ? "*   If applicable, cite potential sources or indicate where factual data is needed ([Source Needed])." : "*   Do not include external sources or references."}
// Removed Image placeholder from prompt as it was removed from the form

**Additional Notes/Instructions:**
${notes.isNotEmpty ? notes : "None"}

**Formatting Requirements:**
*   Use Markdown for formatting.
*   Employ clear headings (H2, H3) and subheadings to structure the content logically.
*   Utilize paragraphs for distinct ideas.
*   Use bullet points or numbered lists where appropriate for clarity and scannability.
*   Ensure the language is fluent and natural for the specified target language (${selectedLanguage}).
*   The final output should be the blog post content ONLY, without any introductory text like "Here is the blog post:".

Generate the blog post now:
''';
  }

  // Call to the Groq API (Keep original)
  final GroqApiService _groqApiService = GroqApiService(
    apiKey: dotjsonenv.env['_groqApiKey'] ?? "",
  );

  @override
  void showErrorSnackBar(String message) {
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
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }
}
