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
import 'package:yoobble/models/tab_controller.dart';
import '../../models/groq_API.dart';
import '../../models/quotas.dart';
import '../../stripe/paywall.dart';
import '../../stripe/stripeinfo.dart';
import '../../utils/responsive.dart';
import 'based_class.dart';

class EmailGenerator extends BaseGenerator {
  const EmailGenerator({
    super.key,
  });

  @override
  _EmailGeneratorState createState() => _EmailGeneratorState();
}

class _EmailGeneratorState extends BaseGeneratorState<EmailGenerator>
    with SingleTickerProviderStateMixin {
  final TextEditingController subjectLineController = TextEditingController();
  final TextEditingController recipientTypeController = TextEditingController();
  final TextEditingController contentPurposeController =
      TextEditingController();
  final TextEditingController keyPointsController = TextEditingController();
  final TextEditingController closingController = TextEditingController();

  // TabController for mobile view
  late TabController _tabController;

  String selectedTone = 'Professional';
  String selectedEmailType = 'Business Communication';
  String selectedLanguage = 'English';
  String selectedFormality = 'Formal';
  String? _errorMessage; // Added for displaying errors

  final List<String> emailTypes = [
    'Business Communication',
    'Customer Service',
    'Internal Communication',
    'Invitation',
    'Announcement',
    'Inquiry',
    'Follow-up',
    'Thank You',
    'Introduction',
    'Newsletter'
  ];

  final List<String> tones = [
    'Professional',
    'Friendly',
    'Urgent',
    'Persuasive',
    'Informative',
    'Enthusiastic',
    'Empathetic',
    'Authoritative'
  ];

  final List<String> formalityLevels = [
    'Very Formal',
    'Formal',
    'Standard',
    'Casual',
    'Informal'
  ];

  final List<String> languages = [
    'English',
    'French',
    'Spanish',
    'German',
    'Italian'
  ];

  // Color scheme
  final Color primaryColor = Color.fromARGB(255, 1, 35, 2); // Green
  final Color secondaryColor = Color.fromARGB(255, 0, 0, 0); // Light green
  final Color accentColor = Color(0xFF2E7D32); // Dark green
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
    _checkSubscriptionStatus();
    // Load quota information
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
        _hasUnlimitedQuota = remaining == -1; // Set unlimited flag
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
        setState(() {
          _isSubscribed = false;
          _isTrialActive = false;
          userSubscriptionPlan = null;
          _isSubscriptionLoading = false; // Ensure loading stops
        });
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

  @override
  void dispose() {
    subjectLineController.dispose();
    recipientTypeController.dispose();
    contentPurposeController.dispose();
    keyPointsController.dispose();
    closingController.dispose();
    _tabController.dispose(); // Dispose TabController
    super.dispose();
  }

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
                      else if (userSubscriptionPlan == 'Pro')
                        // Show Pro-specific message
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.purple[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.purple),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.star, color: Colors.purple[800]),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'You\'ve reached your Pro plan daily limit of ${ApiQuotaManager.proDailyLimit} generations. Upgrade to Standard or Business for unlimited access.',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    color: Colors.purple[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      else // Show standard message for free users
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
    await _checkSubscriptionStatus(); // This updates _isSubscribed

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
    // Subscription status
    if (_isSubscriptionLoading) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: Text("..."),
          ),
        ),
      );
    }

    // Pour les abonnements Standard et Business (quota illimité)
    if (userSubscriptionPlan != null &&
        (userSubscriptionPlan == 'Standard' ||
            userSubscriptionPlan == 'Business')) {
      Color chipColor = Colors.grey[200]!;
      Color textColor = Colors.black87;
      IconData icon = Icons.check_circle_outline; // Default icon

      switch (userSubscriptionPlan) {
        case 'Standard':
          chipColor = Colors.blue[100]!;
          textColor = Colors.blue[800]!;
          icon = Icons.star_border; // Example icon for Standard
          break;
        case 'Business':
          chipColor = Colors.green[100]!;
          textColor = Colors.green[800]!;
          icon = Icons.business; // Example icon for Business
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

    // Affichage spécifique pour les utilisateurs Pro (avec leur quota)
    if (userSubscriptionPlan == 'Pro' && !_isLoadingQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            avatar: Icon(Icons.star, size: 16, color: accentColor),
            label: Text(
              'Pro $_remainingQuota/${ApiQuotaManager.proDailyLimit}',
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            backgroundColor: accentColor.withOpacity(0.2),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Quota display for free users
    if (!_isLoadingQuota && !_hasUnlimitedQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            label: Text(
              '$_remainingQuota/$_dailyLimit',
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

    // Unlimited quota display
    if (!_isLoadingQuota && _hasUnlimitedQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Chip(
            label: Text(
              'Unlimited',
              style: TextStyle(
                color: Colors.green[800],
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
            avatar:
                Icon(Icons.all_inclusive, size: 14, color: Colors.green[800]),
            backgroundColor: Colors.green[50],
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            labelPadding: EdgeInsets.symmetric(horizontal: 4.0),
          ),
        ),
      );
    }

    // Default case: not loading anything specific
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
      // User profile avatar and menu
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
            "Email", // Use the title passed to the widget
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
                                        color: primaryColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        FontAwesomeIcons.envelope,
                                        color: primaryColor,
                                        size: 16,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Generated Email',
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
                                          hintText:
                                              'Generated email content...',
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
                                                        'Email content appears here.',
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
                                        selectedEmailType,
                                        FontAwesomeIcons.envelope,
                                        primaryColor),
                                    _buildBadge(
                                        selectedTone,
                                        FontAwesomeIcons.commentDots,
                                        secondaryColor),
                                    _buildBadge(selectedFormality,
                                        FontAwesomeIcons.feather, accentColor),
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

      // --- Desktop View --- (similar to AdsGenerator)
      desktop: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          shadowColor: Colors.transparent,
          automaticallyImplyLeading:
              false, // Ne met rien par défaut (comme le bouton retour)
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
                                  color: primaryColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  FontAwesomeIcons.envelope,
                                  color: primaryColor,
                                  size: 18,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text(
                                selectedEmailType,
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
                                        'The generated email will appear here...',
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
                                            'Creating your perfect email...',
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
                                                    FontAwesomeIcons
                                                        .envelopeOpenText,
                                                    size: 40,
                                                    color: Colors.grey[300],
                                                  ),
                                                  SizedBox(height: 24),
                                                  Text(
                                                    'Your email will appear here',
                                                    style: TextStyle(
                                                      fontSize: 18,
                                                      color: Colors.grey[400],
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Fill in the form and click "Generate Email" to create your email',
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

                      // Email type and format badges
                      if (generatedContent.isNotEmpty && !isGenerating)
                        Container(
                          margin: EdgeInsets.only(top: 20),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildBadge(
                                selectedEmailType,
                                FontAwesomeIcons.envelope,
                                primaryColor,
                              ),
                              _buildBadge(
                                selectedTone,
                                FontAwesomeIcons.commentDots,
                                secondaryColor,
                              ),
                              _buildBadge(
                                selectedFormality,
                                FontAwesomeIcons.feather,
                                accentColor,
                              ),
                              _buildBadge(
                                selectedLanguage,
                                FontAwesomeIcons.language,
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
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FontAwesomeIcons.envelopeOpenText,
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
                      'Create Professional Emails',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Effective emails for business, service, and communication',
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

        // Type and format
        buildSectionHeader('Email Type & Details', FontAwesomeIcons.envelope),
        SizedBox(height: 20),

        buildDropdown(
          label: 'Email Type',
          value: selectedEmailType,
          items: emailTypes,
          onChanged: (value) {
            setState(() {
              selectedEmailType = value!;
            });
          },
          icon: FontAwesomeIcons.envelopeCircleCheck,
        ),
        SizedBox(height: 16),

        // Subject line
        buildTextField(
          controller: subjectLineController,
          label: 'Subject Line',
          hint: 'Enter an effective subject line',
          icon: FontAwesomeIcons.heading,
          required: true,
        ),
        SizedBox(height: 16),

        // Recipient info
        buildTextField(
          controller: recipientTypeController,
          label: 'Recipient Type',
          hint: 'Prospect, customer, colleague, manager...',
          icon: FontAwesomeIcons.userGroup,
          required: true,
        ),
        SizedBox(height: 16),

        // Purpose
        buildTextField(
          controller: contentPurposeController,
          label: 'Email Purpose',
          hint: 'Inform, sell, thank, resolve an issue...',
          icon: FontAwesomeIcons.bullseye,
          required: true,
        ),
        SizedBox(height: 28),

        // Content details
        buildSectionHeader('Content & Style', FontAwesomeIcons.penFancy),
        SizedBox(height: 20),

        buildTextField(
          controller: keyPointsController,
          label: 'Key Points (separated by commas)',
          hint: 'Main information to include in the email',
          icon: FontAwesomeIcons.listOl,
          maxLines: 3,
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
                label: 'Formality Level',
                value: selectedFormality,
                items: formalityLevels,
                onChanged: (value) {
                  setState(() {
                    selectedFormality = value!;
                  });
                },
                icon: FontAwesomeIcons.handshake,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),

        buildDropdown(
          label: 'Language',
          value: selectedLanguage,
          items: languages,
          onChanged: (value) {
            setState(() {
              selectedLanguage = value!;
            });
          },
          icon: FontAwesomeIcons.language,
        ),
        SizedBox(height: 16),

        // Closing
        buildTextField(
          controller: closingController,
          label: 'Conclusion or Call to Action',
          hint: 'How would you like to end your email?',
          icon: FontAwesomeIcons.arrowRightFromBracket,
          maxLines: 2,
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

        // Quota indicator before generate button - expanded to handle both free and Pro users
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
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _remainingQuota < 5 ? Colors.amber : Colors.blue[300]!,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: _remainingQuota < 5
                      ? Colors.amber[800]
                      : Colors.blue[700],
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    userSubscriptionPlan == 'Pro'
                        ? 'You have $_remainingQuota/${ApiQuotaManager.proDailyLimit} Pro generations remaining today.'
                        : 'You have $_remainingQuota/${ApiQuotaManager.dailyLimit} free generations remaining today.',
                    style: TextStyle(
                      color: _remainingQuota < 5
                          ? Colors.amber[800]
                          : Colors.blue[700],
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
                        'Generate Email',
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
            fontSize: 15,
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
                  fontSize: 12,
                  fontFamily: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.fontFamily), // Use theme font
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              // Add prefix icon inside items for alignment
              selectedItemBuilder: (BuildContext context) {
                return items.map<Widget>((String item) {
                  return Row(
                    children: [
                      Icon(icon, color: primaryColor, size: 18),
                      SizedBox(width: 12),
                      Text(item),
                    ],
                  );
                }).toList();
              },
              items: items.map((String item) {
                return DropdownMenuItem<String>(
                  value: item,
                  child: Text(item), // Display only text in the dropdown list
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
    if (subjectLineController.text.trim().isEmpty ||
        contentPurposeController.text.trim().isEmpty ||
        recipientTypeController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please fill in all required fields (*)';
      });
      showErrorSnackBar(
          'Please fill in at least the subject line, recipient type, and email purpose');
      return;
    }

    // Check if user can make API request based on quota
    final canMakeRequest = await _quotaManager.canMakeApiRequest();
    if (!canMakeRequest) {
      setState(() {
        _errorMessage = userSubscriptionPlan == 'Pro'
            ? "You've reached your Pro plan daily limit. Upgrade to Standard or Business for unlimited access."
            : "You've reached your daily free limit. Upgrade to continue.";
      });
      _showUpgradeDialog();
      return;
    }

    setState(() {
      isGenerating = true;
      generatedContent = '';
    });

    try {
      // Build the prompt for the API
      final prompt = _buildAIPrompt();
      final response = await _groqApiService.generateContent(prompt);

      // Record API usage for users with quotas
      // Standard and Business users don't need usage tracking
      if (!_hasUnlimitedQuota) {
        await _quotaManager.recordApiUsage();
        await _loadRemainingQuota(); // Refresh quota count
      }

      setState(() {
        generatedContent = response.trim(); // Trim whitespace
        generatedContentController.text = response.trim();
        isGenerating = false;
        isCopied = false; // Reset copy/save state
        isSaved = false;
        isEditing = false;
      });
      // Utilisation du mixin pour naviguer
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

  // Build the prompt for the AI API
  String _buildAIPrompt() {
    final String subject = subjectLineController.text;
    final String recipientType = recipientTypeController.text;
    final String purpose = contentPurposeController.text;
    final String keyPoints = keyPointsController.text;
    final String closing = closingController.text;

    return '''
    Generate a complete email with the following characteristics:
    
    Email type: $selectedEmailType
    Subject line: $subject
    Recipient: $recipientType
    Purpose: $purpose
    Key points to include: ${keyPoints.isNotEmpty ? keyPoints : "No specific points mentioned"}
    Conclusion: ${closing.isNotEmpty ? closing : "Use a standard closing appropriate for this type of email"}
    Tone: $selectedTone
    Formality level: $selectedFormality
    Language: $selectedLanguage
    
    Ensure the email is well-structured with an appropriate greeting, introduction, main body, and conclusion. 
    Include a professional signature at the end.
    Generate only the email content, without additional explanations or comments.
    ''';
  }

  // Call to the OpenRouter API
  // In your class initialization
  final GroqApiService _groqApiService = GroqApiService(
    apiKey: dotjsonenv.env['_groqApiKey'] ?? "",
  );

// Then replace the API call in generateContent()

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
