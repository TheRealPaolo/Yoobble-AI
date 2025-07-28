// ignore_for_file: deprecated_member_use, avoid_print, use_build_context_synchronously, library_private_types_in_public_api, depend_on_referenced_packages
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

class AdsGenerator extends BaseGenerator {
  const AdsGenerator({
    super.key,
  });

  @override
  _AdsGeneratorState createState() => _AdsGeneratorState();
}

class _AdsGeneratorState extends BaseGeneratorState<AdsGenerator>
    with SingleTickerProviderStateMixin {
  final TextEditingController productController = TextEditingController();
  final TextEditingController targetAudienceController =
      TextEditingController();
  final TextEditingController uniqueSellingPointController =
      TextEditingController();
  final TextEditingController benefitsController = TextEditingController();
  final TextEditingController callToActionController = TextEditingController();

  // TabController for mobile view
  late TabController _tabController;

  String selectedAdType = 'Google Ads';
  String selectedAdFormat = 'Text';
  String selectedTone = 'Persuasive';
  String selectedObjective = 'Conversion';
  String? _errorMessage;

  final List<String> adTypes = [
    'Google Ads',
    'Facebook Ads',
    'Instagram Ads',
    'LinkedIn Ads',
    'Twitter Ads',
    'Display Ads',
    'Native Ads'
  ];
  final List<String> adFormats = [
    'Text',
    'Image',
    'Video',
    'Story',
    'Carousel'
  ];
  final List<String> adObjectives = [
    'Conversion',
    'Web Traffic',
    'Brand Awareness',
    'Engagement',
    'App Installation',
    'Lead Generation',
    'Sales'
  ];
  final List<String> tones = [
    'Persuasive',
    'Professional',
    'Friendly',
    'Urgent',
    'Informative',
    'Humorous',
    'Emotional'
  ];

  // Improved color scheme
  final Color primaryColor = Colors.black; // Deeper orange
  final Color secondaryColor = Color.fromARGB(255, 26, 17, 0); // Amber gold
  final Color accentColor = Color(0xFF6750A4); // Purple
  final Color backgroundColor = Color(0xFFF8F9FB); // Light gray with blue tint
  final Color cardColor = Colors.white;
  final Color textColor = Color(0xFF1F2937); // Dark gray
  final Color lightTextColor = Color(0xFF6B7280); // Medium gray
  final Color errorColor = Color(0xFFDC2626); // Error red

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
    // Load subscription status
    _checkUserSubscription(); // This will trigger _checkSubscriptionStatus
    // Load quota information (will be refreshed after subscription check)
    _loadRemainingQuota();
    _loadCurrentDailyLimit(); // Load initial daily limit
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
        // Determine unlimited status based on remaining quota value or plan
        // Assuming -1 means unlimited, adjust if ApiQuotaManager signals differently
        _hasUnlimitedQuota = remaining == -1 ||
            (userSubscriptionPlan == 'Standard' ||
                userSubscriptionPlan == 'Business');
        _isLoadingQuota = false;
      });
    } catch (e) {
      setState(() {
        _remainingQuota = 0;
        _hasUnlimitedQuota = false; // Assume limited on error
        _isLoadingQuota = false;
      });
      print('Error loading quota: $e');
    }
  }

  // Load the current daily limit based on subscription plan
  Future<void> _loadCurrentDailyLimit() async {
    try {
      // This method should ideally determine the limit based on the fetched userSubscriptionPlan
      // For now, we'll set it based on the plan state variable after it's loaded.
      final limit =
          await _quotaManager.getCurrentDailyLimit(); // Assumes this exists
      setState(() {
        _dailyLimit =
            limit; // This might be free limit or pro limit depending on ApiQuotaManager logic
      });
    } catch (e) {
      print('Error loading daily limit: $e');
      // Keep default value or handle error appropriately
      if (mounted) {
        setState(() {
          // Fallback based on known plan if manager fails
          if (userSubscriptionPlan == 'Pro') {
            _dailyLimit = ApiQuotaManager.proDailyLimit;
          } else {
            _dailyLimit = ApiQuotaManager.proDailyLimit;
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
    uniqueSellingPointController.dispose();
    benefitsController.dispose();
    callToActionController.dispose();
    _tabController.dispose(); // Dispose TabController
    super.dispose(); // Calls dispose on BaseGeneratorState
  }

  // --- Upgrade Dialog and Navigation ---
  // Using a structure similar to EmailGenerator's dialog for consistency
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
                          fontFamily:
                              'Courier', // Match EmailGenerator style if desired
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

  // Helper to get icon for format type
  IconData getFormatIcon(String format) {
    switch (format) {
      case 'Text':
        return FontAwesomeIcons.alignLeft;
      case 'Image':
        return FontAwesomeIcons.image;
      case 'Video':
        return FontAwesomeIcons.video;
      case 'Story':
        return FontAwesomeIcons.bookOpen;
      case 'Carousel':
        return FontAwesomeIcons.images;
      default:
        return FontAwesomeIcons.ad;
    }
  }

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
        backgroundColor: Colors.white, // Keep original AdsGenerator background
        appBar: AppBar(
          backgroundColor: cardColor,
          surfaceTintColor: cardColor,
          automaticallyImplyLeading: false,
          elevation: 0,
          shadowColor: Colors.grey.withOpacity(0.1),
          title: Text(
            "Ads Generator",
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
              Tab(text: 'Create'),
              Tab(text: 'Preview'),
            ],
            labelColor: primaryColor,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: primaryColor,
            indicatorWeight: 3,
            indicatorSize: TabBarIndicatorSize.label,
          ),
        ),
        body: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 1: Form/Options
              _buildMobileFormView(), // Using existing helper

              // Tab 2: Generated Content Results
              _buildMobileResultsView(), // Using existing helper
            ],
          ),
        ),
      ),

      // --- Desktop View ---
      desktop: Scaffold(
        backgroundColor: Colors.white, // Keep original AdsGenerator background
        appBar: AppBar(
          shadowColor: Colors.transparent,
          automaticallyImplyLeading: false,
          elevation: 0,
          surfaceTintColor: Colors.white,
          backgroundColor: Colors.white,
          actions: appBarActions,
        ),
        body: _buildDesktopView(), // Using existing helper
      ),
    );
  }

  // Mobile Form View (Keep original structure)
  Widget _buildMobileFormView() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Top card with introduction (Keep original)
          Card(
            elevation: 0,
            color: cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryColor.withOpacity(0.8),
                    secondaryColor.withOpacity(0.8)
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
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
                      FontAwesomeIcons.bullhorn,
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
                          'Ad Generator',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Create compelling ads for your campaigns',
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
          ),
          SizedBox(height: 16),

          // Main form card (Keep original structure)
          Card(
            color: cardColor,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type and format section
                  buildSectionHeader(
                      'Ad Configuration', FontAwesomeIcons.sliders),
                  SizedBox(height: 16),
                  _buildMobileDropdownSection(), // Keep original
                  SizedBox(height: 24),

                  // Content details section
                  buildSectionHeader('Ad Content', FontAwesomeIcons.penFancy),
                  SizedBox(height: 16),
                  _buildMobileContentSection(), // Keep original
                  SizedBox(height: 24),

                  // Error message
                  if (_errorMessage != null)
                    _buildErrorMessage(), // Use existing helper

                  // *** START QUOTA DISPLAY LOGIC (Adapted from EmailGenerator) ***
                  // Quota limit reached warning
                  if (!_isLoadingQuota &&
                      !_hasUnlimitedQuota &&
                      _remainingQuota == 0)
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
                            : accentColor
                                .withOpacity(0.1), // Use Pro color base
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _remainingQuota < 5
                              ? Colors.amber
                              : accentColor
                                  .withOpacity(0.3), // Use Pro color base
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

                  // Generate button
                  _buildGenerateButton(), // Use existing helper
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Mobile Results View (Keep original structure)
  Widget _buildMobileResultsView() {
    return SingleChildScrollView(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with title and actions
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
                              FontAwesomeIcons.bullhorn,
                              color: primaryColor, // Match header icon color
                              size: 16,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Generated Ad',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      // Action buttons
                      Row(
                        children: [
                          _buildActionButton(
                            // Keep original
                            isActive: isEditing,
                            activeIcon: Icons.check,
                            inactiveIcon: Icons.edit,
                            onPressed: () => setState(() {
                              isEditing = !isEditing;
                            }),
                            tooltip: isEditing ? 'Done' : 'Edit',
                          ),
                          SizedBox(width: 4),
                          _buildActionButton(
                            // Keep original
                            isActive: isCopied,
                            activeIcon: Icons.check,
                            inactiveIcon: Icons.copy,
                            onPressed: () {
                              final textToCopy = isEditing
                                  ? generatedContentController.text
                                  : generatedContent;
                              if (textToCopy.isNotEmpty) {
                                copyToClipboard(textToCopy);
                              }
                            },
                            tooltip: isCopied ? 'Copied' : 'Copy',
                            activeColor: Colors.green,
                          ),
                          SizedBox(width: 4),
                          _buildActionButton(
                            // Keep original
                            isActive: isSaved,
                            activeIcon: Icons.check,
                            inactiveIcon: Icons.save_outlined,
                            onPressed: saveContent,
                            tooltip: isSaved ? 'Saved' : 'Save',
                            activeColor: Colors.green,
                          ),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  // Preview/edit area (Keep original)
                  Container(
                    height: 60.h, // Adjust height as needed
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    padding: EdgeInsets.all(16),
                    child: isEditing
                        ? TextField(
                            controller: generatedContentController,
                            maxLines: null,
                            expands: true,
                            decoration: InputDecoration.collapsed(
                              hintText: 'Your ad text will appear here...',
                              hintStyle: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 14,
                              ),
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: textColor,
                            ),
                          )
                        : isGenerating
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      color: primaryColor,
                                      strokeWidth: 2,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Creating your ad...',
                                      style: TextStyle(
                                        color: primaryColor,
                                        fontWeight: FontWeight.w500,
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
                                            SizedBox(height: 50), // Add space
                                            Icon(
                                              FontAwesomeIcons.penToSquare,
                                              size: 32,
                                              color: Colors.grey[300],
                                            ),
                                            SizedBox(height: 16),
                                            Text(
                                              'Your ad will appear here',
                                              style: TextStyle(
                                                color: Colors.grey[400],
                                                fontSize: 14,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                            SizedBox(height: 50), // Add space
                                          ],
                                        ),
                                      )
                                    : Text(
                                        generatedContent,
                                        style: TextStyle(
                                          fontSize: 14,
                                          height: 1.5,
                                          color: textColor,
                                        ),
                                      ),
                              ),
                  ),

                  // Ad type badges (Keep original)
                  if (generatedContent.isNotEmpty && !isGenerating)
                    Container(
                      margin: EdgeInsets.only(top: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildBadge(
                            selectedAdType,
                            FontAwesomeIcons.ad,
                            primaryColor,
                          ),
                          _buildBadge(
                            selectedAdFormat,
                            getFormatIcon(selectedAdFormat),
                            secondaryColor,
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
    );
  }

  // Desktop View (Keep original structure)
  Widget _buildDesktopView() {
    return Padding(
      // Added padding around the Row for desktop
      padding: EdgeInsets.all(1.5.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left side - Form (Keep original structure with width)
          SizedBox(
            width: 35.w, // Adjust width as needed
            child: Card(
              color: cardColor,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.grey.shade200),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form header (Keep original)
                    Container(
                      padding: EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor.withOpacity(0.8),
                            secondaryColor.withOpacity(0.8)
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
                            padding: EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              FontAwesomeIcons.bullhorn,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Ad Generator',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(height: 5),
                                Text(
                                  'Create compelling ads for your marketing campaigns',
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

                    // Type and format section
                    buildSectionHeader(
                        'Ad Type & Format', FontAwesomeIcons.rectangleAd),
                    SizedBox(height: 20),
                    _buildDesktopDropdownSection(), // Keep original
                    SizedBox(height: 28),

                    // Content details section
                    buildSectionHeader(
                        'Ad Content Details', FontAwesomeIcons.penFancy),
                    SizedBox(height: 20),
                    _buildDesktopContentSection(), // Keep original
                    SizedBox(height: 28),

                    // Error message if error
                    if (_errorMessage != null)
                      _buildErrorMessage(), // Use existing helper

                    // *** START QUOTA DISPLAY LOGIC (Adapted from EmailGenerator) ***
                    // Quota limit reached warning
                    if (!_isLoadingQuota &&
                        !_hasUnlimitedQuota &&
                        _remainingQuota == 0)
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
                              : accentColor
                                  .withOpacity(0.1), // Use Pro color base
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _remainingQuota < 5
                                ? Colors.amber
                                : accentColor
                                    .withOpacity(0.3), // Use Pro color base
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

                    // Generate button
                    _buildGenerateButton(), // Use existing helper
                  ],
                ),
              ),
            ),
          ),

          SizedBox(width: 2.w), // Keep original spacing

          // Right side - Generated content (Keep original structure)
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with title and actions (Keep original)
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
                                FontAwesomeIcons.bullhorn,
                                color: primaryColor, // Match header icon color
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 16),
                            Text(
                              'Generated Ad',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // Edit button
                            _buildDesktopActionButton(
                              // Keep original
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
                            // Copy button
                            _buildDesktopActionButton(
                              // Keep original
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
                            // Save button
                            _buildDesktopActionButton(
                              // Keep original
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
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        padding: EdgeInsets.all(24),
                        child: isEditing
                            ? TextField(
                                controller: generatedContentController,
                                maxLines: null,
                                expands: true,
                                decoration: InputDecoration(
                                  border: InputBorder.none,
                                  hintText: 'Your ad text will appear here...',
                                  hintStyle: TextStyle(color: Colors.grey[400]),
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
                                          'Creating your perfect ad...',
                                          style: TextStyle(
                                            color: primaryColor,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'This may take a moment',
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
                                            child: Padding(
                                              // Add padding for empty state
                                              padding: EdgeInsets.symmetric(
                                                  vertical: 50.0),
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    FontAwesomeIcons.bullhorn,
                                                    size: 48,
                                                    color: Colors.grey[300],
                                                  ),
                                                  SizedBox(height: 24),
                                                  Text(
                                                    'Your ad will appear here',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey[400],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Fill in the form and click "Generate Ad" to create your ad',
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      color: Colors.grey[400],
                                                    ),
                                                    textAlign: TextAlign.center,
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

                    // Ad type and format badges (Keep original)
                    if (generatedContent.isNotEmpty && !isGenerating)
                      Container(
                        margin: EdgeInsets.only(top: 20),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildBadge(
                              selectedAdType,
                              FontAwesomeIcons.ad,
                              primaryColor,
                            ),
                            _buildBadge(
                              selectedAdFormat,
                              getFormatIcon(selectedAdFormat),
                              secondaryColor,
                            ),
                            _buildBadge(
                              selectedTone,
                              FontAwesomeIcons.commentDots,
                              accentColor,
                            ),
                            _buildBadge(
                              selectedObjective,
                              FontAwesomeIcons.bullseye,
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
    );
  }

  // Mobile Dropdown Section (Keep original)
  Widget _buildMobileDropdownSection() {
    return Column(
      children: [
        buildDropdown(
          label: 'Ad Platform',
          value: selectedAdType,
          items: adTypes,
          onChanged: (value) {
            setState(() {
              selectedAdType = value!;
            });
          },
          icon: FontAwesomeIcons.ad,
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Ad Format',
          value: selectedAdFormat,
          items: adFormats,
          onChanged: (value) {
            setState(() {
              selectedAdFormat = value!;
            });
          },
          icon: getFormatIcon(selectedAdFormat),
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
          label: 'Objective',
          value: selectedObjective,
          items: adObjectives,
          onChanged: (value) {
            setState(() {
              selectedObjective = value!;
            });
          },
          icon: FontAwesomeIcons.bullseye,
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
                label: 'Ad Platform',
                value: selectedAdType,
                items: adTypes,
                onChanged: (value) {
                  setState(() {
                    selectedAdType = value!;
                  });
                },
                icon: FontAwesomeIcons.ad,
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Ad Format',
                value: selectedAdFormat,
                items: adFormats,
                onChanged: (value) {
                  setState(() {
                    selectedAdFormat = value!;
                  });
                },
                icon: getFormatIcon(selectedAdFormat),
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
                label: 'Objective',
                value: selectedObjective,
                items: adObjectives,
                onChanged: (value) {
                  setState(() {
                    selectedObjective = value!;
                  });
                },
                icon: FontAwesomeIcons.bullseye,
              ),
            ),
          ],
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
          hint: 'What are you advertising?',
          icon: FontAwesomeIcons.box,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: targetAudienceController,
          label: 'Target Audience',
          hint: 'Who is this ad targeting?',
          icon: FontAwesomeIcons.userGroup,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: uniqueSellingPointController,
          label: 'Unique Selling Point',
          hint: 'What makes your offer special?',
          icon: FontAwesomeIcons.star,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: benefitsController,
          label: 'Key Benefits',
          hint: 'Main benefits for the customer (optional)',
          icon: FontAwesomeIcons.thumbsUp,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: callToActionController,
          label: 'Call to Action',
          hint: 'What should the viewer do next?',
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
          hint: 'What are you advertising?',
          icon: FontAwesomeIcons.box,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: targetAudienceController,
          label: 'Target Audience',
          hint: 'Who is this ad targeting?',
          icon: FontAwesomeIcons.userGroup,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: uniqueSellingPointController,
          label: 'Unique Selling Point',
          hint: 'What makes your offer special?',
          icon: FontAwesomeIcons.star,
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: benefitsController,
          label: 'Key Benefits',
          hint: 'Main benefits for the customer (optional)',
          icon: FontAwesomeIcons.thumbsUp,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: callToActionController,
          label: 'Call to Action',
          hint: 'What should the viewer do next?',
          icon: FontAwesomeIcons.handPointer,
          required: true,
        ),
      ],
    );
  }

  // Error Message Widget (Keep original)
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
                  color: errorColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500 // Slightly bolder error text
                  ),
            ),
          ),
        ],
      ),
    );
  }

  // Quota Warning Widget (Adapted from EmailGenerator for consistency)
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
                SizedBox(height: 10), // More space before button
                TextButton(
                  // Changed to TextButton like EmailGenerator for consistency
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
        child: isGenerating // Check isGenerating first
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
                  Icon(
                    FontAwesomeIcons.wandMagicSparkles,
                    size: 18,
                    color: Colors.white,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Generate Ad',
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
    Color activeColor = Colors.blue, // Default blue, but can be overridden
    Color inactiveColor = const Color(0xFF6B7280), // Default lightTextColor
  }) {
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

  // Build status chip for subscription/quota (Adapted from EmailGenerator)
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
            style: TextStyle(fontSize: 15, color: textColor),
            decoration: InputDecoration(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 15),
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 12, right: 8),
                child: Icon(icon, color: primaryColor, size: 18),
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
                fontSize: 15,
                fontFamily: Theme.of(context).textTheme.bodyLarge?.fontFamily,
              ),
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              selectedItemBuilder: (BuildContext context) {
                return items.map<Widget>((String item) {
                  // Use a Row to include the icon in the selected item display
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
                  // Display only text in the dropdown list itself
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
    if (text.isEmpty) return; // Avoid copying empty string
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
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
        uniqueSellingPointController.text.trim().isEmpty ||
        callToActionController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all required fields (marked with *)';
        isGenerating = false; // Stop generation
      });
      showErrorSnackBar('Please fill in all required fields (marked with *)');
      return;
    }

    // *** UPDATED QUOTA CHECK ***
    // Check if user can make API request based on quota and plan
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
        // No need to reload daily limit here unless it changes mid-day
      }

      if (mounted) {
        setState(() {
          generatedContent = response.trim(); // Trim whitespace
          generatedContentController.text = response.trim();
          isGenerating = false; // Generation finished
          // isCopied, isSaved, isEditing are already reset at the start
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

  // Build the prompt for the AI API (Keep original)
  String _buildAIPrompt() {
    final String product = productController.text;
    final String audience = targetAudienceController.text;
    final String usp = uniqueSellingPointController.text;
    final String benefits = benefitsController.text;
    final String cta = callToActionController.text;

    // Construct a more detailed and structured prompt
    return '''
Act as an expert digital advertising copywriter. Generate a compelling advertisement for the specified platform and format.

Ad Platform: $selectedAdType
Ad Format: $selectedAdFormat
Campaign Objective: $selectedObjective

Core Information:

Product/Service: $product

Target Audience: $audience (Consider their pain points, desires, and language)

Unique Value Proposition (UVP): $usp (Highlight what makes this offer distinct)

Key Benefits: ${benefits.isNotEmpty ? benefits : "Focus on the main advantages derived from the UVP."}

Desired Tone: $selectedTone

Call to Action (CTA): ${cta.isNotEmpty ? cta : "Choose the most appropriate CTA based on the objective (e.g., 'Learn More', 'Shop Now', 'Sign Up')."}

Instructions:

Adherence: Strictly follow the best practices and character limits (if applicable) for the chosen
$selectedAdType
and
$selectedAdFormat.

Structure: Organize the ad logically (e.g., Headline(s), Body Text/Description, CTA). For formats like Video or Carousel, provide script ideas or text for each slide/scene.

Content: Craft persuasive and engaging copy that resonates with the Target Audience, clearly communicates the UVP and Key Benefits, and incorporates the specified Tone.

Output: Provide only the final ad copy/structure. Do not include introductory phrases like "Here is the ad:" or any explanations.

Example Structure (for Text Ads - adapt for others):
Headline 1: [Compelling Headline 1]
Headline 2: [Compelling Headline 2]
Headline 3: [Optional Compelling Headline 3]
Description 1: [Engaging Description 1]
Description 2: [Optional Engaging Description 2]
Call to Action: [$cta]

Generate the ad now:
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
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  @override
  Widget buildForm() {
    return ResponsiveWidget(
        mobile: _buildMobileFormView(), desktop: _buildDesktopView());
  }
}
