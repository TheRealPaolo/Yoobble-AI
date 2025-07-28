// ignore_for_file: deprecated_member_use, avoid_print, use_build_context_synchronously
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:http/http.dart' as http;
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'dart:html' as html; // Import for web download
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/groq_API.dart';
import '../stripe/paywall.dart';
import '../stripe/stripeinfo.dart';
import '../utils/responsive.dart'; // Assuming usage from citation generator

class AiAgent extends StatefulWidget {
  const AiAgent({super.key});

  @override
  _AiAgentState createState() => _AiAgentState();
}

class _AiAgentState extends State<AiAgent> with TickerProviderStateMixin {
  final TextEditingController _editorController = TextEditingController();
  final TextEditingController _instructionsController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  int wordCount = 0;
  String _summarizedText = '';
  bool _loading = false; // For AI generation loading
  late AnimationController _animationController;
  bool _extracting = false; // For file extraction loading
  final _groqApiKey = dotjsonenv.env['_groqApiKey'] ?? "";
  late GroqApiService _groqApiService;

  // --- Subscription State Variables (Inspired by CitationGeneratorPage) ---
  String? userSubscriptionPlan; // e.g., 'Business', 'Standard', 'Pro', null
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  bool _isTrialActive = false;
  DateTime? _trialEndDate;
  // bool _isSubscribed = false; // Derived from userSubscriptionPlan != null || _isTrialActive
  bool _isSubscriptionLoading = true; // Start as true
  String? customerId;
  String? _errorMessage; // For displaying general errors
  bool _isBusinessTrial =
      false; // New: Flag to track if the trial is for Business plan
  // --- End Subscription State Variables ---

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _editorController.addListener(_updateWordCount);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    // Initialize Groq API service
    _groqApiService = GroqApiService(apiKey: _groqApiKey);
    // Fetch subscription status when the widget initializes
    _checkUserSubscription();
  }

  // --- Subscription Check Logic (Copied & Adapted from CitationGeneratorPage) ---
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
        if (mounted) {
          setState(() {
            _errorMessage = "Error checking account status.";
          });
        }
      }
    }
    return null;
  }

  Future<String?> _fetchSubscriptionPlan(String customerId) async {
    final url = Uri.parse(
        'https://api.stripe.com/v1/customers/$customerId/subscriptions');
    try {
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
          final activeSubscriptions = subsList.where((sub) =>
              sub is Map &&
              (sub['status'] == 'active' || sub['status'] == 'trialing'));

          if (activeSubscriptions.isNotEmpty) {
            final subscription = activeSubscriptions.first;
            final productId = subscription['plan']['product'];

            // Check trial status specifically
            bool isCurrentlyTrialing = false;
            if (subscription['status'] == 'trialing') {
              final trialEnd = subscription['trial_end'];
              if (trialEnd != null) {
                final trialEndDate =
                    DateTime.fromMillisecondsSinceEpoch(trialEnd * 1000);
                // Check if trial end date is in the future
                if (trialEndDate.isAfter(DateTime.now())) {
                  isCurrentlyTrialing = true;

                  // Get product name to determine if this is a Business trial
                  final productName = await _fetchProductName(productId);
                  final isBusinessProduct =
                      productName.toLowerCase() == 'business';

                  if (mounted) {
                    setState(() {
                      _trialEndDate = trialEndDate;
                      _isTrialActive = true;
                      _isBusinessTrial =
                          isBusinessProduct; // Set the business trial flag
                    });
                  }
                }
              }
            }
            // If not currently trialing according to Stripe, ensure our state reflects that
            if (!isCurrentlyTrialing && mounted) {
              setState(() {
                _isTrialActive = false;
                _isBusinessTrial = false;
                _trialEndDate = null;
              });
            }

            return await _fetchProductName(productId);
          } else {
            // No active or trialing subscriptions found
            if (mounted) {
              setState(() {
                _isTrialActive = false;
                _isBusinessTrial = false;
                _trialEndDate = null;
              });
            }
          }
        } else {
          print('Stripe response format unexpected: ${response.body}');
          if (mounted) {
            setState(() {
              _isTrialActive = false;
              _isBusinessTrial = false;
              _trialEndDate = null;
            });
          }
        }
      } else if (response.statusCode == 404) {
        print('Stripe customer or subscription not found.');
        if (mounted) {
          setState(() {
            _isTrialActive = false;
            _isBusinessTrial = false;
            _trialEndDate = null;
          });
        }
      } else {
        print(
            'Error fetching subscription from Stripe: ${response.statusCode} - ${response.body}');
        if (mounted) {
          setState(() {
            _errorMessage = "Error fetching subscription details.";
            _isTrialActive = false;
            _isBusinessTrial = false;
            _trialEndDate = null;
          });
        }
      }
    } catch (e) {
      print('Error connecting to Stripe: $e');
      if (mounted) {
        setState(() {
          _errorMessage = "Network error checking subscription.";
          _isTrialActive = false;
          _isBusinessTrial = false;
          _trialEndDate = null;
        });
      }
    }
    return null; // Return null if no active/trialing plan found or error occurred
  }

  Future<String> _fetchProductName(String productId) async {
    final url = Uri.parse('https://api.stripe.com/v1/products/$productId');
    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $stripeSecretKey'},
      );

      if (response.statusCode == 200) {
        final product = jsonDecode(response.body);
        final productName = product['name'] as String? ?? 'Unknown';

        // Determine plan based on name (adjust keywords as needed)
        if (productName.toLowerCase().contains('business')) {
          return 'Business';
        } else if (productName.toLowerCase().contains('pro')) {
          return 'Pro';
        } else if (productName.toLowerCase().contains('standard')) {
          return 'Standard';
        } else {
          return productName; // Return the actual name if not recognized
        }
      } else {
        print(
            'Error fetching product name from Stripe: ${response.statusCode} - ${response.body}');
        return 'Unknown';
      }
    } catch (e) {
      print('Error fetching product name: $e');
      return 'Unknown';
    }
  }

  Future<void> _checkUserSubscription() async {
    if (!mounted) return;
    setState(() {
      _isSubscriptionLoading = true;
      _errorMessage = null; // Reset error message
    });

    try {
      customerId = await _getCustomerId();
      String? plan;
      if (customerId != null && customerId!.isNotEmpty) {
        plan = await _fetchSubscriptionPlan(customerId!);
      } else {
        // No customer ID, so no subscription or trial
        _isTrialActive = false;
        _isBusinessTrial = false;
        _trialEndDate = null;
      }

      if (mounted) {
        setState(() {
          userSubscriptionPlan = plan;
          // Ensure trial status is consistent if no plan was found
          if (plan == null) {
            _isTrialActive = false;
            _isBusinessTrial = false;
            _trialEndDate = null;
          }
        });
      }
    } catch (e) {
      print("Error during subscription check: $e");
      if (mounted) {
        setState(() {
          _errorMessage = "Failed to check subscription status.";
          userSubscriptionPlan = null;
          _isTrialActive = false;
          _isBusinessTrial = false;
          _trialEndDate = null;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubscriptionLoading = false;
        });
      }
    }
  }

  // Getters for easier access control (Copied from CitationGeneratorPage)
  bool get _isBusinessUser {
    // Check if the plan name is 'Business' (case-insensitive)
    return userSubscriptionPlan?.toLowerCase() == 'business';
  }

  bool get _canUseFeature {
    // Feature requires Business plan OR an active trial
    // If it's an active trial, we now check if it's specifically a Business trial
    return _isBusinessUser || (_isTrialActive && _isBusinessTrial);
  }

  String get _getRemainingTrialDays {
    if (_trialEndDate == null || !_isTrialActive) return "0";
    final difference = _trialEndDate!.difference(DateTime.now());
    // Return 0 if the trial has expired, otherwise return days (minimum 1 if positive)
    return difference.isNegative
        ? "0"
        : (difference.inDays + (difference.inHours % 24 > 0 ? 1 : 0))
            .toString();
  }
  // --- End Subscription Check Logic ---

  // Keep existing navigation logic (can be simplified if needed)
  Future<void> _handleSubscriptionNavigation() async {
    // Navigate based on subscription status
    if (!context.mounted) return;

    // If user has an active plan (any plan) or trial, show info page
    if (userSubscriptionPlan != null || _isTrialActive) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const SubscriptionInfoPage(), // Your actual page
        ),
      );
    } else {
      // Otherwise, show the upgrade/subscribe options
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const SubscriptionBottomSheet(), // Your actual page/modal
        ),
      );
    }
  }

  @override
  void dispose() {
    _editorController.removeListener(_updateWordCount);
    _editorController.dispose();
    _instructionsController.dispose();
    _promptController.dispose();
    _animationController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  void _updateWordCount() {
    if (!mounted) return;
    setState(() {
      wordCount = _editorController.text
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .length;
    });
  }

  Future<void> _uploadFile() async {
    if (!mounted) return;
    setState(() {
      _extracting = true;
      _errorMessage = null;
    });
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'txt',
          'docx',
          'pdf',
          'csv'
        ], // Removed xlsx for simplicity
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        PlatformFile file = result.files.first;
        if (file.bytes != null) {
          String content;
          switch (file.extension?.toLowerCase()) {
            case 'txt':
            case 'csv':
              content = utf8.decode(file.bytes!);
              break;
            case 'docx':
              content = await _extractTextFromDocx(file.bytes!);
              break;
            case 'pdf':
              content = await _extractTextFromPdf(file.bytes!);
              break;
            default:
              throw Exception('Unsupported file format');
          }
          if (mounted) {
            setState(() {
              _editorController.text = content;
              _extracting = false;
            });
          }
        } else {
          if (mounted) setState(() => _extracting = false);
        }
      } else {
        if (mounted) setState(() => _extracting = false);
      }
    } catch (e) {
      print('Error importing file: $e');
      if (mounted) {
        setState(() {
          _extracting = false;
          _errorMessage = 'Error importing file: ${e.toString()}';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing file: ${e.toString()}')),
        );
      }
    }
  }

  // Docx and PDF extraction methods remain the same
  Future<String> _extractTextFromDocx(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final documentXml = archive.findFile('word/document.xml');
    if (documentXml != null) {
      final content = utf8.decode(documentXml.content);
      // Simplified regex focusing on text nodes, might need refinement for complex docs
      final textRegExp = RegExp(r'<w:t[^>]*>(.*?)<\/w:t>', dotAll: true);
      final texts = textRegExp.allMatches(content);
      // Join texts, handling potential XML entities (basic example)
      return texts
          .map((m) => m.group(1)?.replaceAll(RegExp(r'<[^>]+>'), '') ?? '')
          .join(' ');
    }
    return '';
  }

  Future<String> _extractTextFromPdf(List<int> bytes) async {
    try {
      final PdfDocument document = PdfDocument(inputBytes: bytes);
      final PdfTextExtractor extractor = PdfTextExtractor(document);
      final StringBuffer buffer = StringBuffer();

      for (int i = 0; i < document.pages.count; i++) {
        String text = extractor.extractText(startPageIndex: i, endPageIndex: i);
        buffer.writeln(text.trim()); // Trim each page's text
      }

      document.dispose();
      return buffer.toString().trim(); // Trim final result
    } catch (e) {
      print("Error extracting PDF text: $e");
      return "Error: Could not extract text from PDF.";
    }
  }

  void _pasteText() async {
    ClipboardData? clipboardData =
        await Clipboard.getData(Clipboard.kTextPlain);
    if (clipboardData != null && clipboardData.text != null) {
      if (mounted) {
        setState(() {
          _editorController.text = clipboardData.text!;
        });
      }
    }
  }

  void _clearText() {
    if (mounted) {
      setState(() {
        _editorController.clear();
        // Word count update is handled by the listener
      });
    }
  }

  // --- Upgrade Dialog (Adapted from CitationGeneratorPage) ---
  void _showUpgradeDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Using the more stylized dialog from CitationGenerator
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          contentPadding: EdgeInsets.zero,
          content: Container(
            width: MediaQuery.of(context).size.width *
                0.8, // Adjust width as needed
            constraints:
                BoxConstraints(maxWidth: 500), // Max width for larger screens
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
                    color:
                        Colors.black, // Or a theme color like Colors.blue[800]
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
                        'Upgrade for AI Agent Access', // Updated Title
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
                      // Show trial info if applicable, now with clearer Business trial messaging
                      if (_isTrialActive && _isBusinessTrial)
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
                                  'Your Business trial includes full access! You have $_getRemainingTrialDays days left.',
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
                      // If trial but not Business trial, show different message
                      else if (_isTrialActive && !_isBusinessTrial)
                        Container(
                          padding: EdgeInsets.all(12),
                          margin: EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue[800]),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Your current trial doesn\'t include Business features. Upgrade to access the AI Agent.',
                                  style: TextStyle(
                                    fontFamily: 'Courier',
                                    color: Colors.blue[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Main message
                      Text(
                        'The AI Agent requires a Business plan for full functionality, including advanced generation and customization.', // Updated text
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          fontFamily: 'Courier',
                          height: 1.4,
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
                            // Use the navigation handler
                            onPressed: () {
                              Navigator.of(context).pop(); // Close dialog first
                              _handleSubscriptionNavigation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black, // Or theme color
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
                                Icon(
                                  _isTrialActive
                                      ? Icons.info_outline
                                      : Icons
                                          .upgrade, // Change icon if already in trial
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  _isTrialActive
                                      ? 'Manage Plan'
                                      : 'Upgrade Now', // Change text if in trial
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
  // --- End Upgrade Dialog ---

  void _showTalkToAgentDialog() {
    // Use the local controllers for this dialog
    final TextEditingController localInstructionsController =
        TextEditingController(text: _instructionsController.text);
    final TextEditingController localPromptController =
        TextEditingController(text: _promptController.text);

    showDialog(
      context: context,
      builder: (BuildContext context) {
        // Use StatefulBuilder to manage the dialog's internal state if needed (e.g., for button enable/disable)
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
            actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 15),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Talk to Agent',
                  style: TextStyle(
                      fontSize: 18,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.w600),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: "Close",
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ],
            ),
            content: SingleChildScrollView(
              // Makes content scrollable if needed
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Provide instructions and a prompt to guide the AI agent in processing your text.', // More descriptive help text
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontFamily: 'Courier',
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Instructions for AI Agent',
                      style: TextStyle(
                          fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  TextField(
                    controller: localInstructionsController,
                    maxLines: 3, // Allow more lines
                    minLines: 1,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                    decoration: InputDecoration(
                      hintText:
                          "e.g., Act as a helpful assistant summarizing complex topics.",
                      hintStyle: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          color: Colors.grey[500]),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: Colors.black, width: 1.5)),
                      prefixIcon: const Icon(
                        Icons.integration_instructions_outlined,
                        color: Colors.black54,
                        size: 20,
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text('Prompt',
                      style: TextStyle(
                          fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  TextField(
                    controller: localPromptController,
                    maxLines: 4, // Allow more lines
                    minLines: 1,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                    decoration: InputDecoration(
                      hintText:
                          "e.g., Summarize the key findings in bullet points.",
                      hintStyle: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: 12,
                          color: Colors.grey[500]),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.grey.shade300)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              BorderSide(color: Colors.black, width: 1.5)),
                      prefixIcon: const Icon(
                        Icons.text_fields_outlined,
                        color: Colors.black54,
                        size: 20,
                      ),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // --- Subscription Status Display within Dialog ---
                  if (_isSubscriptionLoading)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10.0),
                        child: Row(
                          children: [
                            SizedBox(
                                width: 4,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text("Checking access...",
                                style: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 12,
                                    color: Colors.grey)),
                          ],
                        ))
                  else if (_isBusinessUser)
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.verified_user_outlined,
                              color: Colors.green[700], size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Business Plan: Full access enabled',
                              style: TextStyle(
                                color: Colors.green[800],
                                fontFamily: 'Courier',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isTrialActive && _isBusinessTrial)
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer, color: Colors.amber[800], size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Business Trial: $_getRemainingTrialDays days remaining',
                              style: TextStyle(
                                color: Colors.amber[800],
                                fontFamily: 'Courier',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_isTrialActive && !_isBusinessTrial)
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline,
                              color: Colors.orange[700], size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Current trial does not include Business features',
                              style: TextStyle(
                                color: Colors.orange[800],
                                fontFamily: 'Courier',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  else // Not Business, Not Trial, Not Loading -> Needs Upgrade
                    Container(
                      margin: EdgeInsets.only(bottom: 10),
                      padding:
                          EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline,
                              color: Colors.blue[700], size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Upgrade to Business plan required.',
                              style: TextStyle(
                                color: Colors.blue[800],
                                fontFamily: 'Courier',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // --- End Subscription Status Display ---
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontFamily: 'Courier'),
                ),
              ),
              const SizedBox(width: 10),
              // --- Conditional Generate/Upgrade Button ---
              ElevatedButton.icon(
                icon: Icon(
                  !_canUseFeature
                      ? Icons.upgrade
                      : Icons.auto_awesome, // Different icons
                  color: Colors.white,
                  size: 18,
                ),
                label: Text(
                  !_canUseFeature
                      ? 'Upgrade Plan'
                      : 'Generate', // Different text
                  style: TextStyle(
                      fontFamily: 'Courier', fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: !_canUseFeature
                      ? Colors.blue[700]
                      : Colors.black, // Different colors
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  elevation: 2,
                ),
                onPressed: _isSubscriptionLoading
                    ? null
                    : () {
                        // Disable while loading sub status
                        // Update main controllers before closing
                        _instructionsController.text =
                            localInstructionsController.text;
                        _promptController.text = localPromptController.text;

                        Navigator.of(context).pop(); // Close the dialog

                        if (!_canUseFeature) {
                          _showUpgradeDialog(); // Show upgrade prompt if no access
                        } else {
                          _obtenirReponse(); // Proceed with generation if access granted
                        }
                      },
              ),
              // --- End Conditional Button ---
            ],
          );
        });
      },
    );
  }

  Future<void> _obtenirReponse() async {
    // --- Access Check ---
    if (!_canUseFeature) {
      _showUpgradeDialog();
      return;
    }
    // --- End Access Check ---

    if (!mounted) return;
    setState(() {
      _loading = true; // AI Generation loading
      _summarizedText = ''; // Clear previous result
      _errorMessage = null;
    });
    _animationController.reset();
    _animationController.forward();

    // Switch to the AI Agent tab automatically
    _tabController.animateTo(1);

    // Determine if chunking is needed (rough estimate)
    int approximateChars = _editorController.text.length;
    // Let's set a generous limit, e.g., ~100k chars (adjust based on model limits/performance)
    const int charLimit = 100000;

    try {
      List<String> results = [];
      if (approximateChars > charLimit) {
        // Split the text into chunks (respecting word boundaries)
        List<String> chunks =
            _splitTextIntoChunksByChars(_editorController.text, charLimit);

        for (int i = 0; i < chunks.length; i++) {
          if (!mounted) {
            return; // Check if widget is still mounted between chunks
          }
          // Update loading state to show progress
          setState(() {
            _summarizedText =
                "${results.join('\n\n...\n\n')}\n\nProcessing chunk ${i + 1} of ${chunks.length}...";
          });

          final chunkPrompt =
              '${_instructionsController.text}\n\n${_promptController.text}\n\nPROCESS THE FOLLOWING TEXT CHUNK:\n${chunks[i]}';
          final responseText = await _callGroqAPI(chunkPrompt);
          results.add(responseText);
        }
      } else {
        // Process the entire text at once
        final prompt =
            '${_instructionsController.text}\n\n${_promptController.text}\n\nPROCESS THE FOLLOWING TEXT:\n${_editorController.text}';
        final responseText = await _callGroqAPI(prompt);
        results.add(responseText);
      }

      if (mounted) {
        setState(() {
          _summarizedText = results.join('\n\n'); // Combine results
          _loading = false;
        });
      }
    } catch (e) {
      print('Error during AI generation: $e');
      if (mounted) {
        setState(() {
          _summarizedText =
              'An error occurred during generation.\nPlease check your input or try again later.\n\nError: ${e.toString()}';
          _loading = false;
          _errorMessage = "AI Generation Failed.";
        });
      }
    }
  }

  // --- API Call with Access Check (Updated to use Groq package) ---
  Future<String> _callGroqAPI(String prompt) async {
    // --- Access Check ---
    if (!_canUseFeature) {
      // This shouldn't be reached if _obtenirReponse checks first, but acts as a failsafe
      throw Exception(
          'Access denied: This feature requires a Business subscription or active Business trial.');
    }
    // --- End Access Check ---

    try {
      // Using the Groq package to generate content
      final responseText = await _groqApiService.generateContent(prompt);
      return responseText;
    } catch (e) {
      print("Error with Groq API: $e");
      throw Exception('API Error: ${e.toString()}');
    }
  }
  // --- End API Call ---

  // Helper to split text by character limit, trying to respect word boundaries
  List<String> _splitTextIntoChunksByChars(String text, int maxChars) {
    List<String> chunks = [];
    int startIndex = 0;

    while (startIndex < text.length) {
      int endIndex = startIndex + maxChars;
      if (endIndex >= text.length) {
        // Last chunk
        chunks.add(text.substring(startIndex));
        break;
      }

      // Try to find the last space before the limit
      int lastSpace = text.lastIndexOf(' ', endIndex);
      if (lastSpace > startIndex) {
        // Found a space, split there
        endIndex = lastSpace;
      } else {
        // No space found, force split at maxChars (might cut a word)
        // Or find the next space *after* maxChars if preferred
        int nextSpace = text.indexOf(' ', endIndex);
        if (nextSpace != -1) {
          endIndex = nextSpace;
        }
        // If no space found anywhere nearby, we just split at maxChars
      }

      chunks.add(text.substring(startIndex, endIndex).trim());
      startIndex = endIndex + 1; // Move past the space or split point
    }
    return chunks;
  }

  // Download button and logic remain similar, ensure html import is present
  Widget _buildDownloadButton() {
    return TextButton.icon(
      icon: const Icon(Icons.file_download_outlined,
          color: Colors.black54, size: 20),
      label: const Text(
        'Export', // Add label for clarity
        style: TextStyle(
          color: Colors.black,
          fontFamily: 'Courier',
          fontSize: 13, // Match other button text sizes
        ),
      ),
      style: TextButton.styleFrom(
        padding:
            EdgeInsets.symmetric(horizontal: 10, vertical: 8), // Adjust padding
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
                    fontFamily: 'Courier', fontWeight: FontWeight.bold),
              ),
              children: <Widget>[
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('pdf');
                  },
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  child: const Text('Export as PDF',
                      style: TextStyle(fontFamily: 'Courier')),
                ),
                Divider(height: 1, thickness: 1, indent: 15, endIndent: 15),
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload(
                        'doc'); // Note: Exports as plain text with .doc extension
                  },
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  child: const Text('Export as DOC (Plain Text)',
                      style: TextStyle(fontFamily: 'Courier')),
                ),
                Divider(height: 1, thickness: 1, indent: 15, endIndent: 15),
                SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(context);
                    _handleDownload('txt'); // Added TXT option
                  },
                  padding: EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  child: const Text('Export as TXT',
                      style: TextStyle(fontFamily: 'Courier')),
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
        _tabController.index == 1 ? _summarizedText : _editorController.text;
    if (content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nothing to export.')),
      );
      return;
    }

    try {
      late Uint8List bytes;
      late String fileName;
      late String mimeType;

      switch (format) {
        case 'pdf':
          bytes = await _exportToPdf(content);
          fileName = 'ai_agent_export.pdf';
          mimeType = 'application/pdf';
          break;
        case 'doc': // Plain text saved as .doc
          bytes = Uint8List.fromList(utf8.encode(content));
          fileName = 'ai_agent_export.doc';
          mimeType = 'application/msword'; // Or 'text/plain'
          break;
        case 'txt': // Plain text saved as .txt
          bytes = Uint8List.fromList(utf8.encode(content));
          fileName = 'ai_agent_export.txt';
          mimeType = 'text/plain';
          break;
        // Add cases for CSV/Excel if re-enabled and implemented
        default:
          throw Exception('Unsupported format');
      }

      // Web download logic using dart:html
      final blob = html.Blob([bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;
      html.document.body!.children.add(anchor);

      anchor.click();

      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported as $fileName')),
      );
    } catch (e) {
      print('Error exporting file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error exporting file: ${e.toString()}')),
      );
    }
  }

  // PDF generation remains the same
  Future<Uint8List> _exportToPdf(String content) async {
    final PdfDocument document = PdfDocument();
    final PdfPage page = document.pages.add();
    final Size pageSize = page.getClientSize();
    // Use a standard font that supports common characters
    final PdfFont font = PdfStandardFont(PdfFontFamily.helvetica, 11);

    // Layout the text with automatic wrapping
    final PdfTextElement textElement = PdfTextElement(
      text: content,
      font: font,
      brush: PdfSolidBrush(PdfColor(0, 0, 0)),
    );

    // Define the layout format
    final PdfLayoutFormat layoutFormat = PdfLayoutFormat(
      layoutType: PdfLayoutType.paginate, // Paginate if text exceeds one page
      breakType: PdfLayoutBreakType.fitPage,
    );

    // Draw the text on the page(s)
    textElement.draw(
      page: page,
      bounds: Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
      format: layoutFormat,
    );

    final List<int> bytes = await document.save();
    document.dispose();
    return Uint8List.fromList(bytes);
  }

  // --- Subscription Status Badge Widget ---
  Widget _buildSubscriptionStatusBadge({bool isAppBar = false}) {
    double horizontalPadding = isAppBar ? 8 : 12;
    double verticalPadding = isAppBar ? 4 : 6;
    double fontSize = isAppBar ? 10 : 12;
    IconData iconData = Icons.help_outline; // Default icon
    Color bgColor = Colors.grey.shade200;
    Color fgColor = Colors.black54;
    Color borderColor = Colors.grey.shade400;
    String label = "Checking...";

    if (!_isSubscriptionLoading) {
      if (_isBusinessUser) {
        iconData = Icons.stars;
        bgColor = Colors.green.withOpacity(0.1);
        fgColor = Colors.green.shade800;
        borderColor = Colors.green;
        label = "Business Plan";
      } else if (_isTrialActive && _isBusinessTrial) {
        // Only show remaining days for Business trials
        iconData = Icons.timer;
        bgColor = Colors.amber.withOpacity(0.1);
        fgColor = Colors.amber.shade800;
        borderColor = Colors.amber;
        label = "Business Trial: ${_getRemainingTrialDays}d";
      } else if (_isTrialActive && !_isBusinessTrial) {
        // Regular trial (not Business) - don't show days
        iconData = Icons.hourglass_empty;
        bgColor = Colors.orange.withOpacity(0.1);
        fgColor = Colors.orange.shade800;
        borderColor = Colors.orange;
        label = "Limited Trial"; // Removed days count for non-Business trials
      } else if (userSubscriptionPlan != null) {
        // Handle other plans if needed (e.g., Pro, Standard)
        iconData = Icons.check_circle_outline;
        bgColor = Colors.blue.withOpacity(0.1);
        fgColor = Colors.blue.shade800;
        borderColor = Colors.blue;
        label = "$userSubscriptionPlan Plan"; // Display the fetched plan name
      } else {
        // Not subscribed, not in trial
        iconData = Icons.lock_outline;
        bgColor = Colors.red.withOpacity(0.05);
        fgColor = Colors.red.shade700;
        borderColor = Colors.red.shade300;
        label = "Upgrade Needed";
      }
    }

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding, vertical: verticalPadding),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconData, size: isAppBar ? 14 : 16, color: fgColor),
          SizedBox(width: isAppBar ? 4 : 8),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }
  // --- End Subscription Status Badge ---

  @override
  Widget build(BuildContext context) {
    // Use ScreenUtilInit if needed, otherwise remove ScreenUtil imports/usage
    // ScreenUtil.init(context); // Example initialization

    return ResponsiveWidget(
      // --- MOBILE UI ---
      mobile: Scaffold(
        backgroundColor: Colors.grey.shade50, // Light background
        appBar: AppBar(
          shadowColor: Colors.white,
          surfaceTintColor: Colors.white,
          backgroundColor: Colors.white,
          elevation: 1, // Subtle shadow
          leadingWidth: 0,
          automaticallyImplyLeading:
              false, // Ne met rien par défaut (comme le bouton retour)
          titleSpacing: 0, // Reduce spacing before title
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _uploadFile,
                icon: const Icon(Icons.upload_file_outlined,
                    color: Colors.black54, size: 20),
                label: const Text('Upload',
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Courier',
                      fontSize: 13,
                    )),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8)),
              ),
              TextButton.icon(
                onPressed: _pasteText,
                icon: const Icon(Icons.content_paste_outlined,
                    color: Colors.black54, size: 20),
                label: const Text('Paste',
                    style: TextStyle(
                      color: Colors.black,
                      fontFamily: 'Courier',
                      fontSize: 13,
                    )),
                style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: 8)),
              ),
            ],
          ),
          actions: [
            // Subscription Status Badge in AppBar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child:
                  Center(child: _buildSubscriptionStatusBadge(isAppBar: true)),
            ),
          ],
        ),
        body: Column(
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(
                    child: Text('Original Text',
                        style: TextStyle(fontFamily: 'Courier'))),
                Tab(
                    child: Text('AI Agent Output',
                        style: TextStyle(fontFamily: 'Courier'))),
              ],
              labelColor: Colors.black,
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Colors.black,
              indicatorWeight: 2.5,
            ),
            // Only show error message if there is one (removed upgrade prompt)
            if (_errorMessage != null)
              Container(
                color: Colors.red.shade100,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade700, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text(_errorMessage!,
                            style: TextStyle(
                                color: Colors.red.shade900,
                                fontFamily: 'Courier',
                                fontSize: 12))),
                    IconButton(
                        icon: Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _errorMessage = null),
                        padding: EdgeInsets.zero,
                        constraints: BoxConstraints()),
                  ],
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics:
                    NeverScrollableScrollPhysics(), // Prevent swiping if needed
                children: [
                  // --- Original Text Tab ---
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                        16, 16, 16, 0), // Remove bottom padding
                    child: TextField(
                      controller: _editorController,
                      maxLines: null, // Takes available space
                      expands: true, // Takes available space
                      keyboardType: TextInputType.multiline, // Better keyboard
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Paste or upload your text here...',
                        hintStyle: TextStyle(
                            fontFamily: 'Courier', color: Colors.grey),
                      ),
                      style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 13,
                        height: 1.5, // Improve readability
                      ),
                    ),
                  ),
                  // --- AI Agent Output Tab ---
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Show loading indicator centrally
                          if (_loading)
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 40.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    LoadingAnimationWidget.staggeredDotsWave(
                                        color: Colors.black, size: 40),
                                    SizedBox(height: 16),
                                    Text("AI Agent is processing...",
                                        style: TextStyle(
                                            fontFamily: 'Courier',
                                            color: Colors.grey[700])),
                                  ],
                                ),
                              ),
                            )
                          // If not loading, show results or placeholder/prompt
                          else if (_summarizedText.isNotEmpty)
                            // Use MarkdownBody for rich text display
                            MarkdownBody(
                              data: _summarizedText,
                              selectable: true,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 14,
                                    height: 1.5,
                                    color: Colors.black87),
                                h1: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    height: 1.8),
                                h2: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    height: 1.7),
                                h3: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                    height: 1.6),
                                listBullet: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 14,
                                    height: 1.5),
                                code: TextStyle(
                                    fontFamily: 'Courier',
                                    fontSize: 13,
                                    backgroundColor: Colors.grey[200],
                                    color: Colors.black),
                                codeblockDecoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(4),
                                  border:
                                      Border.all(color: Colors.grey.shade300),
                                ),
                                codeblockPadding: const EdgeInsets.all(10),
                                blockquoteDecoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  border: Border(
                                      left: BorderSide(
                                          color: Colors.blue.shade300,
                                          width: 4)),
                                ),
                                blockquotePadding: const EdgeInsets.all(10),
                              ),
                            )
                          else
                            Center(
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 40.0),
                                child: Text(
                                  'AI output will appear here.\nUse the "Agent" button to generate.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontFamily: 'Courier',
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                      height: 1.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // --- Bottom Action Bar ---
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                      top: BorderSide(color: Colors.grey.shade200, width: 1)),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.grey.withOpacity(0.1),
                        spreadRadius: 0,
                        blurRadius: 5,
                        offset: Offset(0, -2)),
                  ]),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween, // Space out items
                children: [
                  // Agent Button
                  TextButton.icon(
                    onPressed: _showTalkToAgentDialog,
                    icon: Icon(
                      Icons.bubble_chart_outlined, // Use outlined icon
                      color: Colors.black,
                      size: 20,
                    ),
                    label: Text(
                      'Agent',
                      style: TextStyle(
                          fontFamily: 'Courier',
                          color: Colors.black,
                          fontSize: 13),
                    ),
                    style: TextButton.styleFrom(
                        padding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
                  ),
                  // Word Count / Clear / Export / Copy Group
                  Row(
                    children: [
                      // Word Count (always visible)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(
                          '$wordCount words',
                          style: TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                      // Show different buttons based on the active tab
                      if (_tabController.index == 0) // Original Text Tab
                        TextButton(
                          onPressed: _clearText,
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8)),
                          child: Text(
                            'Clear',
                            style: TextStyle(
                                fontFamily: 'Courier',
                                color: Colors.red.shade600,
                                fontSize: 13),
                          ),
                        )
                      else // AI Agent Tab
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.copy_outlined,
                                  size: 20, color: Colors.black54),
                              tooltip: "Copy AI Output",
                              onPressed: _summarizedText.isEmpty
                                  ? null
                                  : () {
                                      // Disable if empty
                                      Clipboard.setData(
                                          ClipboardData(text: _summarizedText));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'AI Agent output copied to clipboard',
                                            style: TextStyle(
                                                fontFamily: 'Courier'),
                                          ),
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                              padding: EdgeInsets.all(8), // Adjust padding
                              constraints:
                                  BoxConstraints(), // Remove default constraints
                            ),
                            SizedBox(width: 4), // Spacing
                            _buildDownloadButton(), // Export button
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // Loading indicator for file extraction
            if (_extracting)
              LinearProgressIndicator(
                  minHeight: 2,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black)),
            // const Padding(
            //   padding: EdgeInsets.all(8.0),
            //   child: Text("Extracting text...", style: TextStyle(fontFamily: 'Courier', color: Colors.grey)),
            // ),
          ],
        ),
      ),

/////////////////////////////////////// --- DESKTOP UI ---///////////////////////////////////////////////////////////////////
      desktop: Padding(
        padding: const EdgeInsets.all(30.0), // Outer padding
        child: Card(
          elevation: 3, // Subtle elevation
          color: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)), // Rounded corners
          clipBehavior: Clip.antiAlias, // Clip content to rounded corners
          child: Scaffold(
            // Nested scaffold for structure within the card
            backgroundColor: Colors.white,
            body: Padding(
              // Padding inside the card
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // --- Desktop Header Row ---
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Desktop subscription status indicator
                      _buildSubscriptionStatusBadge(isAppBar: false),
                    ],
                  ),
                  SizedBox(height: 16), // Spacing after header

                  // Only show error messages, removed the upgrade banner
                  if (_errorMessage != null) // Display errors prominently
                    Container(
                      width: double.infinity,
                      color: Colors.red.shade100,
                      margin: EdgeInsets.only(bottom: 16),
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700, size: 20),
                          SizedBox(width: 12),
                          Expanded(
                              child: Text(_errorMessage!,
                                  style: TextStyle(
                                      color: Colors.red.shade900,
                                      fontFamily: 'Courier',
                                      fontSize: 13))),
                          IconButton(
                              icon: Icon(Icons.close, size: 18),
                              onPressed: () =>
                                  setState(() => _errorMessage = null),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints()),
                        ],
                      ),
                    ),

                  // --- Main Content Area (Two Columns) ---
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- Left Column: Input Editor ---
                        Expanded(
                          flex: 5, // Give slightly more space to input
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade300,
                                  width: 1), // Subtle border
                              // boxShadow: [ // Optional subtle shadow
                              //   BoxShadow(
                              //     color: Colors.grey.withOpacity(0.1),
                              //     spreadRadius: 1, blurRadius: 3, offset: const Offset(0, 1),
                              //   ),
                              // ],
                            ),
                            child: Column(
                              children: [
                                // Input Toolbar
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8)),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text("Input Text",
                                          style: TextStyle(
                                              fontFamily: 'Courier',
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black54)),
                                      Spacer(),
                                      TextButton.icon(
                                        onPressed: _uploadFile,
                                        icon: const Icon(
                                            Icons.upload_file_outlined,
                                            color: Colors.black54,
                                            size: 18),
                                        label: const Text('Upload',
                                            style: TextStyle(
                                                fontFamily: 'Courier',
                                                color: Colors.black,
                                                fontSize: 12)),
                                        style: TextButton.styleFrom(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8)),
                                      ),
                                      SizedBox(width: 4),
                                      TextButton.icon(
                                        onPressed: _pasteText,
                                        icon: const Icon(
                                            Icons.content_paste_outlined,
                                            color: Colors.black54,
                                            size: 18),
                                        label: const Text('Paste',
                                            style: TextStyle(
                                                fontFamily: 'Courier',
                                                color: Colors.black,
                                                fontSize: 12)),
                                        style: TextButton.styleFrom(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8)),
                                      ),
                                      SizedBox(width: 4),
                                      TextButton.icon(
                                        onPressed: _clearText,
                                        icon: const Icon(
                                            Icons.clear_all_outlined,
                                            color: Colors.red,
                                            size: 18),
                                        label: const Text('Clear',
                                            style: TextStyle(
                                                fontFamily: 'Courier',
                                                color: Colors.red,
                                                fontSize: 12)),
                                        style: TextButton.styleFrom(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8)),
                                      ),
                                    ],
                                  ),
                                ),
                                // Text Field Area
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: TextField(
                                      controller: _editorController,
                                      maxLines: null,
                                      expands: true,
                                      keyboardType: TextInputType.multiline,
                                      decoration: const InputDecoration(
                                        border: InputBorder.none,
                                        hintText:
                                            'Start writing, paste text, or upload a file...',
                                        hintStyle: TextStyle(
                                            fontFamily: 'Courier',
                                            color: Colors.grey),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'Courier',
                                        height:
                                            1.6, // Increase line height for desktop
                                      ),
                                    ),
                                  ),
                                ),
                                // Input Footer (Word Count)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    border: Border(
                                        top: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1)),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$wordCount words',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                          fontFamily: 'Courier',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // --- Center Action Button ---
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                icon: Icon(Icons.auto_awesome,
                                    color: Colors.white, size: 20),
                                label: Text("Agent",
                                    style: TextStyle(fontFamily: 'Courier')),
                                onPressed: _showTalkToAgentDialog,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(30)),
                                ),
                              ),
                              if (_extracting) // Show extraction loader here
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2)),
                                      SizedBox(width: 8),
                                      Text("Extracting...",
                                          style: TextStyle(
                                              fontFamily: 'Courier',
                                              fontSize: 11,
                                              color: Colors.grey)),
                                    ],
                                  ),
                                )
                            ],
                          ),
                        ),
                        // --- Right Column: AI Output ---
                        Expanded(
                          flex: 6, // Give slightly more space to output
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey
                                  .shade50, // Slightly different background for output
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: Colors.grey.shade300, width: 1),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Output Toolbar
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey
                                        .shade200, // Darker header for output
                                    borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(8),
                                        topRight: Radius.circular(8)),
                                    border: Border(
                                        bottom: BorderSide(
                                            color: Colors.grey.shade300,
                                            width: 1)),
                                  ),
                                  child: Row(
                                    children: [
                                      Text("AI Agent Output",
                                          style: TextStyle(
                                              fontFamily: 'Courier',
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black54)),
                                      Spacer(),
                                      TextButton.icon(
                                        onPressed: _summarizedText.isEmpty
                                            ? null
                                            : () {
                                                Clipboard.setData(ClipboardData(
                                                    text: _summarizedText));
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                      content: Text(
                                                          'AI Output copied to clipboard')),
                                                );
                                              },
                                        icon: const Icon(Icons.copy_outlined,
                                            color: Colors.black54, size: 18),
                                        label: const Text('Copy',
                                            style: TextStyle(
                                                fontFamily: 'Courier',
                                                color: Colors.black,
                                                fontSize: 12)),
                                        style: TextButton.styleFrom(
                                            padding: EdgeInsets.symmetric(
                                                horizontal: 8)),
                                      ),
                                      SizedBox(width: 4),
                                      _buildDownloadButton(), // Export button here
                                    ],
                                  ),
                                ),
                                // Output Content Area
                                Expanded(
                                  child: Container(
                                    width: double
                                        .infinity, // Ensure it takes full width for scrolling
                                    padding: const EdgeInsets.all(16),
                                    child: _loading
                                        ? Center(
                                            // Central loading animation
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                LoadingAnimationWidget
                                                    .threeRotatingDots(
                                                  color: Colors.black,
                                                  size: 35,
                                                ),
                                                SizedBox(height: 12),
                                                Text("Generating response...",
                                                    style: TextStyle(
                                                        fontFamily: 'Courier',
                                                        color: Colors.grey)),
                                              ],
                                            ),
                                          )
                                        : SingleChildScrollView(
                                            // Scrollable output
                                            child: SelectableText(
                                              // Use SelectableText for easy copying
                                              _summarizedText.isNotEmpty
                                                  ? _summarizedText
                                                  : 'AI generated content will appear here after using the "Agent" button.',
                                              style: TextStyle(
                                                fontSize:
                                                    14, // Slightly larger for output
                                                fontFamily: 'Courier',
                                                height: 1.6,
                                                color:
                                                    _summarizedText.isNotEmpty
                                                        ? Colors.black87
                                                        : Colors.grey[600],
                                              ),
                                            ),
                                          ),
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
        ),
      ),
    );
  }
}
