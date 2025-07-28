// ignore_for_file: avoid_print, deprecated_member_use, use_build_context_synchronously
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:sizer/sizer.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import 'dart:typed_data';
import '../models/groq_API.dart';
import '../utils/responsive.dart';
import '../models/quotas.dart';

class Translate extends StatefulWidget {
  const Translate({super.key});

  @override
  State<Translate> createState() => _TranslateState();
}

class _TranslateState extends State<Translate> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  String _summarizedText = '';
  bool _loading = false;
  int _wordCount = 0;
  String _selectedLanguage = 'English';
  bool _extracting = false;
  late AnimationController _animationController;
  late Animation<double> _animation;

  // Groq API key
  final _groqApiKey = dotjsonenv.env['_groqApiKey'] ?? "";

  // Groq API Service
  late GroqApiService _groqApiService;

  // Instance du gestionnaire de quotas
  final ApiQuotaManager _quotaManager = ApiQuotaManager();
  int _remainingQuota = 0;
  int _totalDailyLimit = ApiQuotaManager.dailyLimit; // Default free limit
  bool _isLoadingQuota = true;

  // Variables pour la vérification de l'abonnement
  String? userSubscriptionPlan;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  bool _isTrialActive = false;
  DateTime? _trialEndDate;
  String? customerId;

  final List<String> _languages = [
    'English',
    'French',
    'German',
    'Spanish',
    'Portuguese',
    'Italian'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _controller.text = "";
    _controller.addListener(_updateWordCount);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _animation =
        Tween<double>(begin: 0, end: 0.99).animate(_animationController);
    _loadRemainingQuota();
    _checkUserSubscription();
    _checkSubscriptionStatus();
    _loadTotalDailyLimit();

    // Initialize Groq API Service
    _groqApiService = GroqApiService(
      apiKey: _groqApiKey,
      model: "llama-3.3-70b-versatile",
    );
  }

  // Load the daily quota limit based on user's plan
  Future<void> _loadTotalDailyLimit() async {
    try {
      final limit = await _quotaManager.getCurrentDailyLimit();
      setState(() {
        _totalDailyLimit = limit == -1 ? ApiQuotaManager.proDailyLimit : limit;
      });
    } catch (e) {
      print('Error loading daily limit: $e');
    }
  }

  // Charger le nombre de requêtes restantes
  Future<void> _loadRemainingQuota() async {
    setState(() {
      _isLoadingQuota = true;
    });

    try {
      final remaining = await _quotaManager.getRemainingQuota();
      setState(() {
        _remainingQuota = remaining;
        _isLoadingQuota = false;
      });
    } catch (e) {
      setState(() {
        _remainingQuota = 0;
        _isLoadingQuota = false;
      });
      print('Error loading quota: $e');
    }
  }

  void _updateWordCount() {
    setState(() {
      _wordCount = _controller.text
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
    });
  }

  // Méthodes de vérification d'abonnement avec Stripe
  Future<String?> _getCustomerId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      DocumentSnapshot userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = userData.data() as Map<String, dynamic>?;
      if (data != null && data.containsKey('customerId')) {
        return data['customerId'] as String?;
      }
    }
    return null;
  }

  Future<String?> _fetchSubscriptionPlan(String customerId) async {
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
      final activeSubscriptions = subscriptions['data'].where(
          (sub) => sub['status'] == 'active' || sub['status'] == 'trialing');

      if (activeSubscriptions.isNotEmpty) {
        final subscription = activeSubscriptions.first;
        final productId = subscription['plan']['product'];

        // Vérifier si l'abonnement est en période d'essai
        if (subscription['status'] == 'trialing') {
          final trialEnd = subscription['trial_end'];
          if (trialEnd != null) {
            _trialEndDate =
                DateTime.fromMillisecondsSinceEpoch(trialEnd * 1000);
            _isTrialActive = true;
          }
        }

        return await _fetchProductName(productId);
      }
    } else {
      print(
          'Error fetching subscription from Stripe: ${response.statusCode} - ${response.body}');
    }
    return null;
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

      if (productName.contains('Standard')) {
        return 'Standard';
      } else if (productName.contains('Pro')) {
        return 'Pro';
      } else if (productName.contains('Business')) {
        return 'Business';
      } else {
        return 'Unknown';
      }
    } else {
      print(
          'Error fetching product name from Stripe: ${response.statusCode} - ${response.body}');
      return 'Unknown';
    }
  }

  Future<void> _checkUserSubscription() async {
    final customerId = await _getCustomerId();
    if (customerId != null) {
      final plan = await _fetchSubscriptionPlan(customerId);
      setState(() {
        userSubscriptionPlan = plan;
      });
    }
  }

  bool get _isPremiumUser {
    return userSubscriptionPlan == 'Standard' ||
        userSubscriptionPlan == 'Pro' ||
        userSubscriptionPlan == 'Business' ||
        _isTrialActive;
  }

  String get _getRemainingTrialDays {
    if (_trialEndDate == null) return "0";
    final difference = _trialEndDate!.difference(DateTime.now()).inDays;
    return difference.toString();
  }

  Future<void> _checkSubscriptionStatus() async {
    setState(() {});

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        // Handle potential null or missing field gracefully
        if (userData.exists &&
            (userData.data() as Map<String, dynamic>)
                .containsKey('customerId')) {
          customerId = userData['customerId'] as String?;
        } else {
          customerId = null; // Ensure customerId is null if not found
        }
      } else {
        customerId = null; // No user, no customer ID
      }

      if (customerId != null && customerId!.isNotEmpty) {
        // Check not empty
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
          // Check if 'data' exists and is a list
          if (subscriptions.containsKey('data') &&
              subscriptions['data'] is List) {
            final subsList = subscriptions['data'] as List;
            final activeSubscriptions = subsList
                .where((sub) => sub is Map && sub['status'] == 'active');
            final trialSubscriptions = subsList
                .where((sub) => sub is Map && sub['status'] == 'trialing');

            if (activeSubscriptions.isNotEmpty ||
                trialSubscriptions.isNotEmpty) {
              setState(() {});
            } else {
              setState(() {});
            }
          } else {
            // Handle case where 'data' is not as expected
            print('Stripe response format unexpected: ${response.body}');
            setState(() {});
          }
        } else {
          // Handle non-200 responses (e.g., 404 if customer has no subscriptions)
          print('Stripe API error: ${response.statusCode} ${response.body}');
          setState(() {});
        }
      } else {
        // No customer ID, so not subscribed
        setState(() {});
      }
    } catch (e) {
      print('Error checking subscription: $e');
      setState(() {});
    } finally {
      // Use mounted check before calling setState in async finally block
      if (mounted) {
        setState(() {});
      }
    }
  }

  // Get the display text for the quota chip
  String get _getQuotaDisplayText {
    if (_isPremiumUser) {
      if (_isTrialActive && userSubscriptionPlan == null) {
        return 'Trial (${_getRemainingTrialDays}d)';
      } else if (userSubscriptionPlan == 'Pro') {
        // For Pro users, show the actual quota usage
        return '$_remainingQuota/$_totalDailyLimit';
      } else {
        return userSubscriptionPlan ?? 'Premium';
      }
    } else {
      return '$_remainingQuota/${ApiQuotaManager.dailyLimit}';
    }
  }

  // Get background color for quota chip
  Color get _getQuotaChipColor {
    if (_isPremiumUser) {
      if (_isTrialActive && userSubscriptionPlan == null) {
        return Colors.amber[700]!;
      } else if (userSubscriptionPlan == 'Pro') {
        // For Pro users, use color based on remaining quota
        if (_remainingQuota < 5) {
          return Colors.red[700]!;
        } else if (_remainingQuota < 10) {
          return Colors.orange;
        } else {
          return Colors.green[700]!;
        }
      } else {
        return Colors.green[700]!;
      }
    } else {
      if (_remainingQuota < 5) {
        return Colors.red[700]!;
      } else if (_remainingQuota < 10) {
        return Colors.orange;
      } else {
        return Colors.grey[200]!;
      }
    }
  }

  // Get text color for quota chip
  Color get _getQuotaTextColor {
    if (_isPremiumUser) {
      return Colors.white;
    } else {
      return _remainingQuota < 5 ? Colors.white : Colors.black;
    }
  }

  late TabController _tabController;
  @override
  Widget build(BuildContext context) {
    return ResponsiveWidget(
        mobile: SafeArea(
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leadingWidth: 0,
              automaticallyImplyLeading:
                  false, // Ne met rien par défaut (comme le bouton retour)
              titleSpacing: 0, // Reduce spacing before title
              title: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(left: 3.w),
                    child: DropdownButton<String>(
                      dropdownColor: Colors.white,
                      focusColor: Colors.white,
                      value: _selectedLanguage,
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedLanguage = newValue!;
                        });
                      },
                      items: _languages
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value,
                              style: const TextStyle(
                                color: Colors.black,
                                fontFamily: 'Courier',
                              )),
                        );
                      }).toList(),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _importFile,
                    icon: const Icon(Icons.cloud_upload, color: Colors.black),
                    label: const Text('Upload',
                        style: TextStyle(
                          color: Colors.black,
                          fontFamily: 'Courier',
                        )),
                  ),
                ],
              ),
              actions: [
                // Affichage du statut d'abonnement ou du quota restant
                if (!_isLoadingQuota)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: Chip(
                        label: Text(
                          _getQuotaDisplayText,
                          style: TextStyle(
                            color: _getQuotaTextColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                        backgroundColor: _getQuotaChipColor,
                        padding: EdgeInsets.symmetric(horizontal: 4),
                      ),
                    ),
                  ),
              ],
            ),
            backgroundColor: Colors.white,
            body: Column(
              children: [
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: 'Original'),
                    Tab(text: 'translated text'),
                  ],
                  labelColor: Colors.black,
                  unselectedLabelColor: Colors.black,
                  indicatorColor: Colors.black,
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _controller,
                          maxLines: null,
                          expands: true,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: SingleChildScrollView(
                          child: _summarizedText.isEmpty
                              ? const Text(
                                  'translated text will appear here...',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                  ),
                                )
                              : MarkdownBody(
                                  data: _summarizedText,
                                  selectable: true,
                                  styleSheet: MarkdownStyleSheet(
                                    h1: const TextStyle(
                                      fontSize: 24,
                                      color: Colors.blue,
                                      fontFamily: 'Courier',
                                    ),
                                    code: const TextStyle(
                                      fontSize: 14,
                                      color: Color.fromARGB(255, 0, 35, 2),
                                      fontFamily: 'Courier',
                                    ),
                                    h2: const TextStyle(
                                      fontSize: 24,
                                      color: Colors.blue,
                                      fontFamily: 'Courier',
                                    ),
                                    h3: const TextStyle(
                                      fontSize: 24,
                                      color: Colors.white,
                                      fontFamily: 'Courier',
                                    ),
                                    h1Align: WrapAlignment.center,
                                    h2Align: WrapAlignment.center,
                                    codeblockPadding: const EdgeInsets.all(8),
                                    codeblockDecoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: const Color.fromARGB(
                                          255, 195, 191, 181),
                                    ),
                                    tableBody: const TextStyle(
                                      color: Colors.black,
                                      fontFamily: 'Courier',
                                    ),
                                    tableHeadAlign: TextAlign.center,
                                    tableHead: const TextStyle(
                                      color: Colors.blue,
                                      fontFamily: 'Courier',
                                    ),
                                    tableCellsDecoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(4),
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      ElevatedButton(
                        onPressed: (!_isPremiumUser && _remainingQuota == 0) ||
                                _loading
                            ? null
                            : () {
                                _summarizeText();
                                setState(() {
                                  _tabController.animateTo(1);
                                });
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          disabledBackgroundColor: Colors.grey,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                        ),
                        child: const Text('translate',
                            style:
                                TextStyle(fontSize: 16, color: Colors.white)),
                      ),

                      // Quota indicator for mobile
                      if (!_isLoadingQuota &&
                          !_isPremiumUser &&
                          _remainingQuota == 0)
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8.0),
                            child: Text(
                              'Daily limit reached',
                              style: TextStyle(
                                color: Colors.red,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),

                      const Spacer(),
                      _buildDownloadButton(),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: _summarizedText));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                              'translate copied to clipboard',
                              style: TextStyle(
                                fontFamily: 'Courier',
                              ),
                            )),
                          );
                        },
                      ),
                      Text(
                        '$_wordCount words',
                        style: const TextStyle(
                          fontFamily: 'Courier',
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _controller.clear();
                            _updateWordCount();
                          });
                        },
                        child: const Text(
                          'Clear',
                          style: TextStyle(
                              fontFamily: 'Courier', color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_extracting)
                  const Text(
                    "Loading...",
                    style:
                        TextStyle(fontFamily: 'Courier', color: Colors.black),
                  ),
              ],
            ),
          ),
        ),

//////////////////////////////////////////////////////////DESKTOP//////////////////////////////////////////////////////////////////////
        desktop: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Card(
            elevation: 5,
            child: Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                backgroundColor: Colors.white,
                elevation: 0,
                leading: const Icon(Icons.translate, color: Colors.black),
                title: Row(
                  children: [
                    DropdownButton<String>(
                      focusColor: Colors.white,
                      dropdownColor: Colors.white,
                      value: _selectedLanguage,
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedLanguage = newValue!;
                        });
                      },
                      items: _languages
                          .map<DropdownMenuItem<String>>((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(" To $value",
                              style: const TextStyle(
                                color: Colors.black,
                                fontFamily: 'Courier',
                              )),
                        );
                      }).toList(),
                    ),
                    SizedBox(width: 24),
                    // Quota or subscription status indicator for desktop
                    if (!_isLoadingQuota)
                      Center(
                        child: Chip(
                          label: Text(
                            _getQuotaDisplayText,
                            style: TextStyle(
                              color: _getQuotaTextColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          backgroundColor: _getQuotaChipColor,
                          padding: EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
              ),
              body: Stack(
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Container(
                          padding: EdgeInsets.only(left: 1.w),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: EdgeInsets.only(top: 2.h, bottom: 2.h),
                                child: Text(
                                  'translate your text effectively',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontFamily: 'Courier',
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  TextButton.icon(
                                    onPressed: _importFile,
                                    icon: const Icon(Icons.cloud_upload,
                                        color: Colors.black),
                                    label: const Text('Upload',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: 'Courier',
                                        )),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: _pasteText,
                                    icon: const Icon(Icons.content_paste,
                                        color: Colors.black),
                                    label: const Text('Paste',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: 'Courier',
                                        )),
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: (!_isPremiumUser &&
                                                _remainingQuota == 0) ||
                                            _loading
                                        ? null
                                        : _summarizeText,
                                    icon: const Icon(Icons.summarize,
                                        color: Colors.black),
                                    label: const Text('translate',
                                        style: TextStyle(
                                          color: Colors.black,
                                          fontFamily: 'Courier',
                                        )),
                                  ),
                                ],
                              ),

                              // Quota warning message for desktop
                              if (!_isLoadingQuota &&
                                  !_isPremiumUser &&
                                  _remainingQuota == 0)
                                Container(
                                  margin: EdgeInsets.symmetric(vertical: 16),
                                  padding: EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning, color: Colors.red),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Daily API Limit Reached',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.red[800],
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              'You\'ve reached your daily free limit of ${ApiQuotaManager.dailyLimit} translations. Upgrade to a paid plan for unlimited access.',
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

                              const SizedBox(height: 16),
                              Expanded(
                                child: TextField(
                                  controller: _controller,
                                  maxLines: null,
                                  expands: true,
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '$_wordCount words',
                                    style: const TextStyle(
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _controller.clear();
                                        _updateWordCount();
                                      });
                                    },
                                    child: const Text(
                                      'Clear',
                                      style: TextStyle(
                                          fontFamily: 'Courier',
                                          color: Colors.black),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Container(
                          color: Colors.grey[100],
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('translation',
                                      style: TextStyle(
                                        fontFamily: 'Courier',
                                      )),
                                  Row(
                                    children: [
                                      Text(
                                        '${_summarizedText.split(' ').length} words',
                                        style: const TextStyle(
                                          fontFamily: 'Courier',
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.copy),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(
                                              text: _summarizedText));
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            const SnackBar(
                                                content: Text(
                                              'Translation copied to clipboard',
                                              style: TextStyle(
                                                fontFamily: 'Courier',
                                              ),
                                            )),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: _summarizedText.isEmpty
                                      ? const Text(
                                          'translated text will appear here',
                                          style: TextStyle(
                                            fontFamily: 'Courier',
                                          ),
                                        )
                                      : MarkdownBody(
                                          data: _summarizedText,
                                          selectable: true,
                                          styleSheet: MarkdownStyleSheet(
                                            h1: const TextStyle(
                                              fontSize: 24,
                                              color: Colors.blue,
                                              fontFamily: 'Courier',
                                            ),
                                            code: const TextStyle(
                                              fontSize: 14,
                                              color:
                                                  Color.fromARGB(255, 0, 35, 2),
                                              fontFamily: 'Courier',
                                            ),
                                            h2: const TextStyle(
                                              fontSize: 24,
                                              color: Colors.blue,
                                              fontFamily: 'Courier',
                                            ),
                                            h3: const TextStyle(
                                              fontSize: 24,
                                              color: Colors.white,
                                              fontFamily: 'Courier',
                                            ),
                                            h1Align: WrapAlignment.center,
                                            h2Align: WrapAlignment.center,
                                            codeblockPadding:
                                                const EdgeInsets.all(8),
                                            codeblockDecoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              color: const Color.fromARGB(
                                                  255, 195, 191, 181),
                                            ),
                                            tableBody: const TextStyle(
                                              color: Colors.black,
                                              fontFamily: 'Courier',
                                            ),
                                            tableHeadAlign: TextAlign.center,
                                            tableHead: const TextStyle(
                                              color: Colors.blue,
                                              fontFamily: 'Courier',
                                            ),
                                            tableCellsDecoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Align(
                                  alignment: Alignment.bottomRight,
                                  child: _buildDownloadButton()),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_loading)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.5),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Finishing loading...',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontFamily: 'Courier',
                                ),
                              ),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: 200,
                                child: AnimatedBuilder(
                                  animation: _animation,
                                  builder: (context, child) {
                                    return LinearProgressIndicator(
                                      value: _animation.value,
                                      backgroundColor: Colors.grey[300],
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                              Colors.blue),
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ),
                    ),
                  if (_extracting)
                    const Text(
                      "Loading...",
                      style:
                          TextStyle(fontFamily: 'Courier', color: Colors.black),
                    ),
                ],
              ),
            ),
          ),
        ));
  }

  Widget _buildDownloadButton() {
    return TextButton.icon(
      icon: const Icon(Icons.file_download, color: Colors.black),
      label: const Text(
        '',
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'Courier',
        ),
      ),
      onPressed: () {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return SimpleDialog(
              backgroundColor: Colors.white,
              title: const Text(
                'Choose export format',
                style: TextStyle(
                  fontFamily: 'Courier',
                ),
              ),
              children: <Widget>[
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('pdf');
                  },
                  child: const Text(
                    'Export as PDF',
                    style: TextStyle(
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('doc');
                  },
                  child: const Text(
                    'Export as DOC',
                    style: TextStyle(
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('csv');
                  },
                  child: const Text(
                    'Export as CSV',
                    style: TextStyle(
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('excel');
                  },
                  child: const Text(
                    'Export as Excel',
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _handleDownload(String format) async {
    String content =
        _summarizedText.isEmpty ? _controller.text : _summarizedText;
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No content to export')),
      );
      return;
    }

    try {
      late Uint8List bytes;
      late String fileName;

      switch (format) {
        case 'pdf':
          bytes = await _exportToPdf(content);
          fileName = 'export.pdf';
          break;
        case 'doc':
          bytes = await _exportToDoc(content);
          fileName = 'export.doc';
          break;
        case 'csv':
          bytes = await _exportToCsv(content);
          fileName = 'export.csv';
          break;
        case 'excel':
          bytes = await _exportToExcel(content);
          fileName = 'export.xlsx';
          break;
        default:
          throw Exception('Unsupported format');
      }

      final blob = html.Blob([bytes]);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;
      html.document.body!.children.add(anchor);

      anchor.click();

      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
    } catch (e) {
      print('Error exporting file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting file: $e')),
      );
    }
  }

  Future<Uint8List> _exportToPdf(String content) async {
    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();
    page.graphics.drawString(
      content,
      PdfStandardFont(PdfFontFamily.helvetica, 12),
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
      bounds: Rect.fromLTWH(
          0, 0, page.getClientSize().width, page.getClientSize().height),
    );

    final List<int> bytes = await document.save();
    document.dispose();

    return Uint8List.fromList(bytes);
  }

  Future<Uint8List> _exportToDoc(String content) async {
    return Uint8List.fromList(utf8.encode(content));
  }

  Future<Uint8List> _exportToCsv(String content) async {
    return Uint8List.fromList(utf8.encode(content.replaceAll(' ', ',')));
  }

  Future<Uint8List> _exportToExcel(String content) async {
    var excel = Excel.createExcel();
    var sheet = excel['Sheet1'];
    sheet.appendRow(content.split(' '));

    return Uint8List.fromList(excel.encode()!);
  }

  void _pasteText() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _controller.text = data.text!;
      });
    }
  }

  void _importFile() async {
    setState(() {
      _extracting = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'docx', 'pdf', 'xlsx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;
        if (file.bytes != null) {
          String content;
          switch (file.extension) {
            case 'txt':
              content = utf8.decode(file.bytes!);
              break;
            case 'docx':
              content = await _extractTextFromDocx(file.bytes!);
              break;
            case 'pdf':
              content = await _extractTextFromPdf(file.bytes!);
              break;
            case 'xlsx':
              content = await _extractTextFromExcel(file.bytes!);
              break;
            default:
              throw Exception('Unsupported file format');
          }
          setState(() {
            _controller.text = content;
            _extracting = false;
          });
        }
      }
    } catch (e) {
      print('Error importing file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing file: $e')),
      );
      setState(() {
        _extracting = false;
      });
    }
  }

  Future<String> _extractTextFromDocx(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentXml = archive.findFile('word/document.xml');
    if (documentXml != null) {
      final content = utf8.decode(documentXml.content);
      final regExp = RegExp(r'<w:p[^>]*>.*?</w:p>', dotAll: true);
      final paragraphs = regExp.allMatches(content);
      return paragraphs.map((paragraph) {
        final textRegExp = RegExp(r'<w:t[^>]*>(.*?)</w:t>', dotAll: true);
        final texts = textRegExp.allMatches(paragraph.group(0)!);
        return texts.map((text) => text.group(1)).join(' ');
      }).join('\n\n');
    }
    return '';
  }

  Future<String> _extractTextFromPdf(List<int> bytes) async {
    final PdfDocument document = PdfDocument(inputBytes: bytes);
    final PdfTextExtractor extractor = PdfTextExtractor(document);
    final StringBuffer buffer = StringBuffer();

    for (int i = 0; i < document.pages.count; i++) {
      String text = extractor.extractText(startPageIndex: i, endPageIndex: i);
      buffer.writeln(text);
      buffer.writeln(); // Add an extra newline between pages
    }

    document.dispose();
    return buffer.toString();
  }

  Future<String> _extractTextFromExcel(List<int> bytes) async {
    final excel = Excel.decodeBytes(bytes);
    final StringBuffer buffer = StringBuffer();
    for (var table in excel.tables.keys) {
      buffer.writeln('Sheet: $table');
      for (var row in excel.tables[table]!.rows) {
        buffer.writeln(row.map((cell) => cell?.value ?? '').join('\t'));
      }
      buffer.writeln();
    }
    return buffer.toString();
  }

  void _summarizeText() async {
    // Vérifier si l'utilisateur peut faire une requête API
    final canMakeRequest = await _quotaManager.canMakeApiRequest();
    if (!canMakeRequest) {
      showErrorSnackBar(
          'You have reached your daily limit of ${ApiQuotaManager.dailyLimit} API requests. Please upgrade to a paid plan for unlimited access.');
      return;
    }

    _obtenirReponse();
  }

  // Afficher un message d'erreur
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

  String _getPrompt() {
    switch (_selectedLanguage) {
      case 'English':
        return 'Translate the following text in English : ${_controller.text}, dont change the text sens or approch make just a translate ';
      case 'French':
        return 'Translate the following text in French : ${_controller.text}, dont change the text sens or approch make just a translate ';
      case 'German':
        return 'Translate the following text in German : ${_controller.text}, dont change the text sens or approch make just a translate ';
      case 'Spanish':
        return 'Translate the following text in Spanish : ${_controller.text}, dont change the text sens or approch make just a translate ';
      case 'Portuguese':
        return 'Translate the following text in Portuguese : ${_controller.text}, dont change the text sens or approch make just a translate ';
      case 'Italian':
        return 'Translate the following text in Italian : ${_controller.text}, dont change the text sens or approch make just a translate ';
      default:
        return 'Please summarize the following text in English ${_controller.text}';
    }
  }

  Future<void> _obtenirReponse() async {
    setState(() {
      _loading = true;
    });
    _animationController.reset();
    _animationController.forward();

    int approximateTokenCount = _controller.text.length ~/ 4;

    if (approximateTokenCount > 8192) {
      List<String> chunks = _splitTextIntoChunks(_controller.text, 131072);
      List<String> summaries = [];

      for (String chunk in chunks) {
        try {
          final responseText = await _groqApiService
              .generateContent('${_getPrompt()} CHUNK $chunk');
          summaries.add(responseText);
        } catch (e) {
          print('Error: $e');
          summaries.add('An error occurred while processing chunk');
        }
      }

      setState(() {
        _summarizedText = summaries.join('\n\n');
      });
    } else {
      try {
        final responseText =
            await _groqApiService.generateContent(_getPrompt());
        setState(() {
          _summarizedText = responseText;
        });

        // Enregistrer l'utilisation de l'API après une requête réussie
        await _quotaManager.recordApiUsage();

        // Mettre à jour le quota restant
        await _loadRemainingQuota();
      } catch (e) {
        print('Error: $e');
        setState(() {
          _summarizedText = 'An error occurred while translating text: $e';
        });
      }
    }

    setState(() {
      _loading = false;
    });
    _animationController.stop();
  }

  List<String> _splitTextIntoChunks(String text, int maxTokens) {
    List<String> words = text.split(' ');
    List<String> chunks = [];
    String currentChunk = '';

    for (String word in words) {
      if ((currentChunk.length + word.length) ~/ 4 < maxTokens) {
        currentChunk += '$word ';
      } else {
        chunks.add(currentChunk.trim());
        currentChunk = '$word ';
      }
    }

    if (currentChunk.isNotEmpty) {
      chunks.add(currentChunk.trim());
    }

    return chunks;
  }

  @override
  void dispose() {
    _controller.removeListener(_updateWordCount);
    _controller.dispose();
    _animationController.dispose();
    super.dispose();
  }
}
