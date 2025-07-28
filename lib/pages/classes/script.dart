// ignore_for_file: deprecated_member_use, avoid_print, use_build_context_synchronously, library_private_types_in_public_api, depend_on_referenced_packages, file_names, overridden_fields, avoid_types_as_parameter_names
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

class ScriptGenerator extends BaseGenerator {
  const ScriptGenerator({
    super.key,
  });

  @override
  _ScriptGeneratorState createState() => _ScriptGeneratorState();
}

class _ScriptGeneratorState extends BaseGeneratorState<ScriptGenerator>
    with SingleTickerProviderStateMixin {
  // Controllers (original)
  final TextEditingController titleController = TextEditingController();
  final TextEditingController genreController = TextEditingController();
  final TextEditingController premiseController = TextEditingController();
  final TextEditingController charactersController = TextEditingController();
  final TextEditingController settingController = TextEditingController();
  final TextEditingController toneController = TextEditingController();

  // New controller for series continuation
  final TextEditingController continuationInputController =
      TextEditingController();

  // State variables for tab view
  late TabController _tabController;

  // Firebase variables for conversation memory
  String? currentConversationId;
  List<Map<String, dynamic>> conversationHistory = [];
  bool isTokenLimitReached = false;

  // Chapter tracking
  int currentChapter = 1;
  bool isChapterMode = false;
  // Flag to indicate if the *next* generation request is for a new chapter
  bool _isPreparingNewChapter = false;

  // Floating button states
  bool isContinuationPanelVisible = false;

  String selectedScriptType = 'Screenplay';
  String selectedFormat = 'Scene';
  String selectedLength = 'Short';
  String? _errorMessage;

  final List<String> scriptTypes = [
    'Screenplay',
    'Short Film',
    'TV Episode',
    'Movie Scene',
    'Commercial',
    'YouTube Video',
    'Social Media Story',
    'Documentary',
    'Animation',
    'Novel',
    'Wattpad' // Added Wattpad style
  ];

  final List<String> formatTypes = [
    'Scene',
    'Dialogue',
    'Monologue',
    'Action Sequence',
    'Montage',
    'Cold Open',
    'Full Script',
    'Chapter' // Added Chapter format for Wattpad and novels
  ];

  final List<String> lengthOptions = ['Short', 'Medium', 'Long', 'Extended'];

  // Improved color scheme
  final Color primaryColor = Color(0xFF1E293B); // Dark blue-gray
  final Color secondaryColor =
      Color(0xFF334155); // Lighter blue-gray (Used for Pro)
  final Color accentColor = Color(0xFF3B82F6); // Bright blue accent
  final Color backgroundColor = Color(0xFFF8F9FB); // Light gray with blue tint
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
    // Load any existing conversation for the current user
    _loadExistingConversation();
  }

  // --- Firebase Conversation Management ---
  Future<void> _loadExistingConversation() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('scriptConversations')
          .where('isActive', isEqualTo: true)
          .orderBy('lastUpdated', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        setState(() {
          currentConversationId = doc.id;
          conversationHistory =
              List<Map<String, dynamic>>.from(doc['messages'] ?? []);

          // Populate fields if conversation exists
          final metadata = doc['metadata'] as Map<String, dynamic>?;
          if (metadata != null) {
            titleController.text = metadata['title'] ?? '';
            genreController.text = metadata['genre'] ?? '';
            premiseController.text = metadata['premise'] ?? '';
            charactersController.text = metadata['characters'] ?? '';
            settingController.text = metadata['setting'] ?? '';
            toneController.text = metadata['tone'] ?? '';

            // Set dropdown values if they exist
            if (metadata['scriptType'] != null) {
              selectedScriptType = metadata['scriptType'];
            }
            if (metadata['format'] != null) selectedFormat = metadata['format'];
            if (metadata['length'] != null) selectedLength = metadata['length'];

            // Set chapter information if this is a continued story
            if (metadata['currentChapter'] != null) {
              currentChapter = metadata['currentChapter'];
              isChapterMode = true;
            }

            // If there are messages, populate the generated content with the last AI response
            if (conversationHistory.isNotEmpty) {
              for (int i = conversationHistory.length - 1; i >= 0; i--) {
                if (conversationHistory[i]['role'] == 'assistant') {
                  generatedContent = conversationHistory[i]['content'];
                  generatedContentController.text = generatedContent;
                  break;
                }
              }
            }
          }
        });
      }
    } catch (e) {
      print('Error loading existing conversation: $e');
    }
  }

  Future<void> _saveConversation({bool isNewConversation = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Prepare the metadata for the conversation
      final metadata = {
        'title': titleController.text,
        'genre': genreController.text,
        'premise': premiseController.text,
        'characters': charactersController.text,
        'setting': settingController.text,
        'tone': toneController.text,
        'scriptType': selectedScriptType,
        'format': selectedFormat,
        'length': selectedLength,
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      // Add chapter information if in chapter mode
      if (isChapterMode) {
        metadata['currentChapter'] = currentChapter;
      }

      if (isNewConversation || currentConversationId == null) {
        // Create a new conversation document
        final newDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scriptConversations')
            .add({
          'createdAt': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
          'isActive': true,
          'messages': conversationHistory,
          'metadata': metadata,
        });

        // Mark all other conversations as inactive
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scriptConversations')
            .where('isActive', isEqualTo: true)
            .where(FieldPath.documentId, isNotEqualTo: newDoc.id)
            .get()
            .then((snapshot) {
          for (var doc in snapshot.docs) {
            doc.reference.update({'isActive': false});
          }
        });

        setState(() {
          currentConversationId = newDoc.id;
        });
      } else {
        // Update existing conversation
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('scriptConversations')
            .doc(currentConversationId)
            .update({
          'lastUpdated': FieldValue.serverTimestamp(),
          'messages': conversationHistory,
          'metadata': metadata,
        });
      }
    } catch (e) {
      print('Error saving conversation: $e');
    }
  }

  Future<void> _startNewConversation() async {
    setState(() {
      // Clear all fields
      titleController.clear();
      genreController.clear();
      premiseController.clear();
      charactersController.clear();
      settingController.clear();
      toneController.clear();

      // Reset to defaults
      selectedScriptType = 'Screenplay';
      selectedFormat = 'Scene';
      selectedLength = 'Short';

      // Clear generated content and history
      generatedContent = '';
      generatedContentController.clear();
      conversationHistory = [];
      currentConversationId = null;

      // Reset chapter tracking and continuation state
      currentChapter = 1;
      isChapterMode = false;
      _isPreparingNewChapter = false;
      isTokenLimitReached = false;
      isContinuationPanelVisible = false;

      // Navigate to form tab
      _tabController.animateTo(0);
    });

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Started a new script. All fields have been cleared.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _continueScript({bool isNewChapter = false}) {
    // Set the flag indicating the *next* generation is intended as a new chapter
    setState(() {
      _isPreparingNewChapter = isNewChapter;
      // Show the continuation panel
      isContinuationPanelVisible = true;
    });
  }

  Future<void> _generateContinuation() async {
    if (continuationInputController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please enter continuation instructions'),
          backgroundColor: errorColor,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Hide the panel and start generating state
    setState(() {
      isContinuationPanelVisible = false;
      isGenerating = true;
    });

    try {
      // Store state before generation for post-generation updates
      bool wasPreparingNewChapter = _isPreparingNewChapter;
      int chapterBeforeGeneration =
          currentChapter; // Chapter of the content BEFORE this generation

      // Build a continuation prompt that includes context
      String previousContent = generatedContent;
      String continuationPrompt = _buildContinuationPrompt(
        previousContent: previousContent,
        continuationInstructions: continuationInputController.text,
        isStartingNewChapter: wasPreparingNewChapter,
        previousChapterNumber: chapterBeforeGeneration,
      );

      // Add user instructions to conversation history
      conversationHistory.add({
        'role': 'user',
        'content':
            'Continuation request (${wasPreparingNewChapter ? "New Chapter" : "Continue"}): ${continuationInputController.text}',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Call API with the continuation prompt
      final response =
          await _groqApiService.generateContent(continuationPrompt);

      // Record API usage for quota management
      if (!_hasUnlimitedQuota) {
        await _quotaManager.recordApiUsage();
        await _loadRemainingQuota();
      }

      // Add AI response to conversation history
      conversationHistory.add({
        'role': 'assistant',
        'content': response.trim(),
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Update the generated content and state AFTER successful generation
      if (mounted) {
        setState(() {
          // If this generation was intended as a new chapter, increment chapter number
          if (wasPreparingNewChapter) {
            currentChapter++;
            isChapterMode = true; // Ensure chapter mode is active
          }

          // For chapter mode or Wattpad, append content if it's not the first chapter
          if (isChapterMode && currentChapter > 1 && wasPreparingNewChapter) {
            generatedContent +=
                "\n\n${response.trim()}"; // Append for new chapters
          } else {
            // Replace for regular continuation or the first chapter
            generatedContent = response.trim();
          }
          generatedContentController.text = generatedContent;
          isGenerating = false;
          continuationInputController.clear();
          _isPreparingNewChapter = false; // Reset the preparation flag
        });

        // Save updated conversation
        await _saveConversation();

        // Check token limit for future reference
        _checkTokenLimit();

        // Switch to results tab
        _tabController.navigateToResultsTabIfMobile(context);
      }
    } catch (e) {
      print('Error during continuation generation: $e');
      if (mounted) {
        setState(() {
          isGenerating = false;
          _errorMessage = 'Failed to generate continuation. Please try again.';
          _isPreparingNewChapter = false; // Reset flag on error too
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error generating continuation. Please try again.'),
            backgroundColor: errorColor,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: EdgeInsets.all(16),
          ),
        );
      }
    }
  }

  String _buildContinuationPrompt({
    required String previousContent,
    required String continuationInstructions,
    required bool
        isStartingNewChapter, // Flag indicating if this GENERATION is a new chapter
    required int
        previousChapterNumber, // The number of the chapter BEFORE this generation
  }) {
    // Create a base prompt that keeps context from the original story
    String baseContext = '''
You are continuing a script/story that was previously generated. Follow these instructions carefully.
The previous part ended like this:

# PREVIOUS CONTENT (Last ~2000 characters for context)
${previousContent.substring(previousContent.length > 2000 ? previousContent.length - 2000 : 0)}

# CONTINUATION INSTRUCTIONS
$continuationInstructions

# STYLE REQUIREMENTS
- Maintain the same writing style, tone, and formatting as the previous content.
- Keep the same characters and setting consistent with the previous part.
- Follow the same formatting conventions ($selectedScriptType style).
''';

    // Add special instructions for chapters if needed
    if (isStartingNewChapter) {
      baseContext += '''
# CHAPTER FORMATTING
- This is **Chapter ${previousChapterNumber + 1}**.
- Start with a clear chapter heading: "Chapter ${previousChapterNumber + 1}" or an appropriate chapter title.
- Ensure this continues the narrative from Chapter $previousChapterNumber in a coherent way.
''';
    } else if (isChapterMode) {
      // If already in chapter mode but not starting a NEW one, continue the current chapter
      baseContext += '''
# CONTINUING CURRENT CHAPTER ($currentChapter)
- You are continuing the current chapter. Do not add a new chapter heading.
- Continue the narrative seamlessly from the end of the previous content.
''';
    }

    // Special instructions for Wattpad style
    if (selectedScriptType == 'Wattpad') {
      baseContext += '''
# WATTPAD STYLE INSTRUCTIONS
- Use the same format as shown in the previous content with dialogue lines following "- Character line"
- Separate paragraphs with a blank line
- Use descriptive narrative between dialogues to set scenes and express emotions
- If starting a new chapter (as indicated above), use clear chapter headers like "Chapter ${previousChapterNumber + 1}"
- Keep character voices consistent
- DO NOT use screenplay formatting - use novel style formatting appropriate for Wattpad
''';
    }

    baseContext += '''
# FINAL INSTRUCTION
Generate the continuation now, picking up naturally from where the previous content ended, applying all instructions above.
''';

    return baseContext;
  }

  void _checkTokenLimit() {
    // Roughly estimate token count (words ÷ 0.75 is a common approximation)
    // Sum the lengths of all messages in the history
    int totalLength = conversationHistory
        .map((msg) => (msg['content'] as String? ?? '').length)
        .fold(0, (sum, length) => sum + length);

    // Simple character count approximation (1 token is roughly 4 characters)
    int approximateTokens = totalLength ~/ 4;

    // Warn if approaching token limits (around 15k for context window)
    if (approximateTokens > 12000) {
      setState(() {
        isTokenLimitReached = true;
      });

      // Show warning to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Approaching token limit for this conversation. Consider starting a new series to maintain quality.',
            style: TextStyle(color: Colors.white),
          ),
          backgroundColor: Colors.orange[700],
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 6),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: EdgeInsets.all(16),
          action: SnackBarAction(
            label: 'New Series',
            textColor: Colors.white,
            onPressed: _startNewConversation,
          ),
        ),
      );
    } else {
      setState(() {
        isTokenLimitReached = false;
      });
    }
  }
  // --- End Firebase Conversation Management ---

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
    genreController.dispose();
    premiseController.dispose();
    charactersController.dispose();
    settingController.dispose();
    toneController.dispose();
    continuationInputController.dispose();
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

  // Helper to get icon for script type
  IconData getScriptTypeIcon(String type) {
    switch (type) {
      case 'Screenplay':
        return FontAwesomeIcons.fileLines;
      case 'Short Film':
        return FontAwesomeIcons.film;
      case 'TV Episode':
        return FontAwesomeIcons.tv;
      case 'Movie Scene':
        return FontAwesomeIcons.video; // Changed icon
      case 'Commercial':
        return FontAwesomeIcons.rectangleAd; // Changed icon
      case 'YouTube Video':
        return FontAwesomeIcons.youtube;
      case 'Social Media Story':
        return FontAwesomeIcons.instagram;
      case 'Documentary':
        return FontAwesomeIcons.bookOpenReader; // Changed icon
      case 'Animation':
        return FontAwesomeIcons.wandMagicSparkles; // Changed icon
      case 'Novel':
        return FontAwesomeIcons.book; // Book icon for novel
      case 'Wattpad':
        return FontAwesomeIcons.bookOpen; // Book icon for Wattpad
      default:
        return FontAwesomeIcons.film;
    }
  }

  // Helper to get icon for format type
  IconData getFormatIcon(String format) {
    switch (format) {
      case 'Scene':
        return FontAwesomeIcons.clapperboard; // Changed icon
      case 'Dialogue':
        return FontAwesomeIcons.comments;
      case 'Monologue':
        return FontAwesomeIcons.comment;
      case 'Action Sequence':
        return FontAwesomeIcons.personRunning;
      case 'Montage':
        return FontAwesomeIcons.images;
      case 'Cold Open':
        return FontAwesomeIcons.doorOpen;
      case 'Full Script':
        return FontAwesomeIcons.scroll; // Changed icon
      case 'Chapter':
        return FontAwesomeIcons.bookmark; // Bookmark for chapters
      default:
        return FontAwesomeIcons.fileLines;
    }
  }

  // --- Helper to build Status Chip (Adapted Logic) ---
  Widget _buildStatusChip() {
    // Loading state
    if (_isSubscriptionLoading || _isLoadingQuota) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Center(
          child: Text(
            '...',
            style: TextStyle(
              color: lightTextColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
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
            "Script Generator", // Keep original title
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
          child: Stack(
            children: [
              TabBarView(
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
                      // Wrap results in a card
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
                                        isChapterMode
                                            ? FontAwesomeIcons.bookOpen
                                            : FontAwesomeIcons.clapperboard,
                                        color: primaryColor,
                                        size: 16,
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      isChapterMode
                                          ? 'Chapter $currentChapter'
                                          : 'Generated Script',
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
                                              .isNotEmpty) {
                                            copyToClipboard(isEditing
                                                ? generatedContentController
                                                    .text
                                                : generatedContent);
                                          }
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
                                          color: textColor,
                                          fontFamily:
                                              selectedScriptType == 'Wattpad'
                                                  ? 'Georgia'
                                                  : 'Courier New'))
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
                                              Text(
                                                  isChapterMode
                                                      ? 'Creating chapter ${currentChapter + (_isPreparingNewChapter ? 1 : 0)}...' // Show next chapter or current + 1
                                                      : 'Creating script...',
                                                  style: TextStyle(
                                                      color: primaryColor,
                                                      fontWeight:
                                                          FontWeight.w500))
                                            ]))
                                      : SingleChildScrollView(
                                          child: generatedContent.isEmpty
                                              ? Center(
                                                  child: Padding(
                                                      padding:
                                                          EdgeInsets.symmetric(
                                                              vertical: 50.0),
                                                      child: Text(
                                                          isChapterMode
                                                              ? 'Chapter content appears here'
                                                              : 'Script appears here',
                                                          style: TextStyle(
                                                              color: Colors
                                                                  .grey[400]))))
                                              : Text(generatedContent,
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      height: 1.5,
                                                      color: textColor,
                                                      fontFamily:
                                                          selectedScriptType ==
                                                                  'Wattpad'
                                                              ? 'Georgia'
                                                              : 'Courier New')),
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
                                    _buildBadge(
                                        selectedScriptType,
                                        getScriptTypeIcon(selectedScriptType),
                                        primaryColor),
                                    _buildBadge(
                                        selectedFormat,
                                        getFormatIcon(selectedFormat),
                                        secondaryColor != Colors.black
                                            ? secondaryColor
                                            : primaryColor.withOpacity(0.7)),
                                    _buildBadge(selectedLength,
                                        FontAwesomeIcons.ruler, accentColor),
                                    if (titleController
                                        .text.isNotEmpty) // Add title badge
                                      _buildBadge(
                                          titleController.text,
                                          FontAwesomeIcons.heading,
                                          Color(0xFF10B981)), // Emerald green
                                    if (isChapterMode)
                                      _buildBadge(
                                          "Chapter $currentChapter",
                                          FontAwesomeIcons.bookOpen,
                                          Colors.purple),
                                    if (isTokenLimitReached) // Add token warning badge
                                      _buildBadge(
                                          "Token Limit Warning",
                                          Icons.warning_amber,
                                          Colors.orange[700]!),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Tab 2: Generated Content Results (Empty State - Moved above)
                ],
              ),

              // Conditional floating action menu (only visible when content exists)
              if (generatedContent.isNotEmpty &&
                  !isGenerating &&
                  !isContinuationPanelVisible)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton(
                    onPressed: () {
                      // Show options menu
                      showModalBottomSheet(
                        context: context,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        builder: (context) => _buildSeriesOptionsModal(),
                      );
                    },
                    backgroundColor: primaryColor, // Use primary color
                    child: Icon(Icons.more_vert,
                        color: Colors.white), // Use dots icon
                  ),
                ),

              // Continuation input panel
              if (isContinuationPanelVisible)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: Offset(0, -2),
                        ),
                      ],
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(20),
                        topRight: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _isPreparingNewChapter
                                  ? 'Create Chapter ${currentChapter + 1}' // Show NEXT chapter number
                                  : 'Continue Story',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: textColor,
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  isContinuationPanelVisible = false;
                                  _isPreparingNewChapter =
                                      false; // Reset flag on close
                                });
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: continuationInputController,
                          decoration: InputDecoration(
                            hintText: 'Enter instructions for continuation...',
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: EdgeInsets.all(16),
                          ),
                          maxLines: 3,
                        ),
                        SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _generateContinuation,
                            style: ElevatedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Generate Continuation',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
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
        body: Stack(
          children: [
            // Main Content
            Padding(
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
                                        isChapterMode
                                            ? FontAwesomeIcons.bookOpen
                                            : FontAwesomeIcons.clapperboard,
                                        color: primaryColor,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Text(
                                      isChapterMode
                                          ? 'Chapter $currentChapter' // Correctly display current chapter
                                          : 'Generated Script',
                                      style: TextStyle(
                                        fontSize: 11, // Larger for desktop
                                        fontWeight: FontWeight.bold,
                                        color: textColor,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                                SingleChildScrollView(
                                  // Wrap action buttons in SingleChildScrollView
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    // Desktop action buttons
                                    children: [
                                      if (generatedContent.isNotEmpty &&
                                          !isGenerating)
                                        _buildDesktopActionButton(
                                          isActive: false,
                                          label: isChapterMode
                                              ? 'New Chapter'
                                              : 'Continue',
                                          icon: isChapterMode
                                              ? Icons.add
                                              : Icons.play_arrow,
                                          onPressed: () => _continueScript(
                                              isNewChapter:
                                                  isChapterMode), // Pass intent
                                          activeColor: accentColor,
                                        ),
                                      SizedBox(width: 4),
                                      if (generatedContent.isNotEmpty &&
                                          !isGenerating)
                                        _buildDesktopActionButton(
                                          isActive: false,
                                          label: 'New serie',
                                          icon: Icons.fiber_new,
                                          onPressed: _startNewConversation,
                                          activeColor: Colors.deepPurple,
                                        ),
                                      SizedBox(width: 8),
                                      // Modified Edit, Copy, Save to be IconButtons only
                                      Tooltip(
                                        message: isEditing
                                            ? 'Done Editing'
                                            : 'Edit Content',
                                        child: IconButton(
                                          icon: Icon(
                                              isEditing
                                                  ? Icons.check
                                                  : Icons.edit,
                                              color: isEditing
                                                  ? primaryColor
                                                  : lightTextColor),
                                          onPressed: () => setState(() {
                                            isEditing = !isEditing;
                                          }),
                                          padding: EdgeInsets.all(8),
                                          splashRadius: 24,
                                          iconSize: 13, // Decreased size
                                        ),
                                      ),
                                      SizedBox(width: 4), // Increased space
                                      Tooltip(
                                        message: isCopied
                                            ? 'Copied'
                                            : 'Copy Content',
                                        child: IconButton(
                                          icon: Icon(
                                              isCopied
                                                  ? Icons.check
                                                  : Icons.copy,
                                              color: isCopied
                                                  ? Colors.green
                                                  : lightTextColor),
                                          onPressed: () {
                                            if (generatedContent.isNotEmpty) {
                                              copyToClipboard(isEditing
                                                  ? generatedContentController
                                                      .text
                                                  : generatedContent);
                                            }
                                          },
                                          padding: EdgeInsets.all(8),
                                          splashRadius: 24,
                                          iconSize: 13, // Decreased size
                                        ),
                                      ),
                                      SizedBox(width: 8), // Increased space
                                      Tooltip(
                                        message:
                                            isSaved ? 'Saved' : 'Save Content',
                                        child: IconButton(
                                          icon: Icon(
                                              isSaved
                                                  ? Icons.check
                                                  : Icons.save_outlined,
                                              color: isSaved
                                                  ? Colors.green
                                                  : lightTextColor),
                                          onPressed: saveContent,
                                          padding: EdgeInsets.all(8),
                                          splashRadius: 24,
                                          iconSize: 13, // Decreased size
                                        ),
                                      ),
                                    ],
                                  ),
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
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        decoration: InputDecoration.collapsed(
                                            hintText: '...'),
                                        style: TextStyle(
                                            fontSize: 16,
                                            height: 1.6,
                                            color: textColor,
                                            fontFamily:
                                                selectedScriptType == 'Wattpad'
                                                    ? 'Georgia'
                                                    : 'Courier New'))
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
                                                Text(
                                                    isChapterMode
                                                        ? 'Creating chapter ${currentChapter + (_isPreparingNewChapter ? 1 : 0)}...' // Show NEXT chapter or current + 1
                                                        : 'Creating script...',
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
                                                        padding: EdgeInsets
                                                            .symmetric(
                                                                vertical: 50.0),
                                                        child: Column(
                                                            /* Empty State Column */ mainAxisAlignment:
                                                                MainAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Icon(
                                                                  isChapterMode
                                                                      ? FontAwesomeIcons
                                                                          .bookOpen
                                                                      : FontAwesomeIcons
                                                                          .clapperboard,
                                                                  size: 48,
                                                                  color: Colors
                                                                          .grey[
                                                                      300]),
                                                              SizedBox(
                                                                  height: 24),
                                                              Text(
                                                                  isChapterMode
                                                                      ? 'Chapter content appears here'
                                                                      : 'Script appears here',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          18,
                                                                      color: Colors
                                                                              .grey[
                                                                          400],
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w500)),
                                                              SizedBox(
                                                                  height: 12),
                                                              Text(
                                                                  'Fill form & click Generate',
                                                                  style: TextStyle(
                                                                      fontSize:
                                                                          14,
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
                                                        color: textColor,
                                                        fontFamily:
                                                            selectedScriptType ==
                                                                    'Wattpad'
                                                                ? 'Georgia'
                                                                : 'Courier New')),
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
                                    _buildBadge(
                                        selectedScriptType,
                                        getScriptTypeIcon(selectedScriptType),
                                        primaryColor),
                                    _buildBadge(
                                        selectedFormat,
                                        getFormatIcon(selectedFormat),
                                        secondaryColor != Colors.black
                                            ? secondaryColor
                                            : primaryColor.withOpacity(0.7)),
                                    _buildBadge(selectedLength,
                                        FontAwesomeIcons.ruler, accentColor),
                                    _buildBadge(
                                        titleController.text.isNotEmpty
                                            ? titleController.text
                                            : "Untitled",
                                        FontAwesomeIcons.heading,
                                        Color(0xFF10B981)), // Emerald green
                                    if (isChapterMode)
                                      _buildBadge(
                                          "Chapter $currentChapter",
                                          FontAwesomeIcons.bookOpen,
                                          Colors.purple),
                                    if (isTokenLimitReached)
                                      _buildBadge(
                                          "Token Limit Warning",
                                          Icons.warning_amber,
                                          Colors.orange[700]!),
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

            // Continuation input panel for desktop (positioned at bottom right)
            if (isContinuationPanelVisible)
              Positioned(
                right: 24,
                bottom: 24,
                width: 40.w,
                child: Card(
                  // Set background to white
                  color: Colors.white,
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                    _isPreparingNewChapter // Icon based on *preparation* flag
                                        ? Icons.bookmark
                                        : Icons.play_arrow,
                                    color: primaryColor),
                                SizedBox(width: 12),
                                Text(
                                  _isPreparingNewChapter
                                      ? 'Create Chapter ${currentChapter + 1}' // Show NEXT chapter number based on current chapter
                                      : 'Continue Story',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  isContinuationPanelVisible = false;
                                  _isPreparingNewChapter =
                                      false; // Reset flag on close
                                });
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: 11),
                        Text(
                          'Provide instructions to continue the narrative:',
                          style: TextStyle(
                            color: textColor,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 12),
                        TextField(
                          controller: continuationInputController,
                          decoration: InputDecoration(
                            hintText:
                                'E.g., "The protagonist discovers a hidden letter" or "Add a plot twist"',
                            filled: true,
                            fillColor: Colors.grey[50],
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            contentPadding: EdgeInsets.all(16),
                          ),
                          maxLines: 4,
                        ),
                        SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  isContinuationPanelVisible = false;
                                  _isPreparingNewChapter =
                                      false; // Reset flag on cancel
                                });
                              },
                              child: Text('Cancel'),
                            ),
                            SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: _generateContinuation,
                              style: ElevatedButton.styleFrom(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 24, vertical: 12),
                                backgroundColor: primaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(
                                'Generate',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
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

  // Build the series options modal (for mobile)
  Widget _buildSeriesOptionsModal() {
    return Container(
      padding: EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Story Options',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          SizedBox(height: 24),

          // Continue option
          _buildModalOption(
            icon: isChapterMode ? Icons.bookmark : Icons.play_arrow,
            title: isChapterMode ? 'New Chapter' : 'Continue Story',
            subtitle: isChapterMode
                ? 'Create Chapter ${currentChapter + 1}' // Show NEXT chapter number
                : 'Continue from where the story left off',
            onTap: () {
              Navigator.pop(context);
              _continueScript(isNewChapter: isChapterMode); // Pass intent
            },
            color: accentColor,
          ),

          SizedBox(height: 16),

          // New series option
          _buildModalOption(
            icon: Icons.fiber_new,
            title: 'New Series',
            subtitle: 'Start a completely new script or story',
            onTap: () {
              Navigator.pop(context);
              _startNewConversation();
            },
            color: Colors.deepPurple,
          ),

          // Only show convert to chapters option if not already in chapter mode
          if (!isChapterMode && generatedContent.isNotEmpty)
            Column(
              children: [
                SizedBox(height: 16),
                _buildModalOption(
                  icon: FontAwesomeIcons.bookOpen,
                  title: 'Convert to Chapter Series',
                  subtitle: 'Turn current content into Chapter 1 of a series',
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      isChapterMode = true;
                      currentChapter = 1; // Set current content as Chapter 1
                      selectedFormat = 'Chapter';

                      // If not already a novel/wattpad, change to novel
                      if (selectedScriptType != 'Wattpad' &&
                          selectedScriptType != 'Novel') {
                        selectedScriptType = 'Novel';
                      }

                      // Save these changes
                      _saveConversation();
                    });

                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Converted to Chapter 1 of a series'),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  color: Colors.teal,
                ),
              ],
            ),

          // Show token limit warning if applicable
          if (isTokenLimitReached)
            Column(
              children: [
                SizedBox(height: 24),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.amber[800]),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This conversation is approaching token limits. Consider starting a new series for best results.',
                          style: TextStyle(
                            color: Colors.amber[800],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

          SizedBox(height: 16),
        ],
      ),
    );
  }

  // Helper to build modal options
  Widget _buildModalOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(12),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  // Mobile Dropdown Section (Keep original)
  Widget _buildMobileDropdownSection() {
    return Column(
      children: [
        buildDropdown(
          label: 'Script Type',
          value: selectedScriptType,
          items: scriptTypes,
          onChanged: (value) {
            setState(() {
              selectedScriptType = value!;

              // Auto-select Chapter format for Wattpad or Novel
              if (value == 'Wattpad' || value == 'Novel') {
                selectedFormat = 'Chapter';
                isChapterMode = true;
              }
            });
          },
          icon: getScriptTypeIcon(selectedScriptType),
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Content Format',
          value: selectedFormat,
          items: formatTypes,
          onChanged: (value) {
            setState(() {
              selectedFormat = value!;

              // Enable chapter mode if 'Chapter' is selected
              if (value == 'Chapter') {
                isChapterMode = true;
              }
            });
          },
          icon: getFormatIcon(selectedFormat),
        ),
        SizedBox(height: 16),
        buildDropdown(
          label: 'Length',
          value: selectedLength,
          items: lengthOptions,
          onChanged: (value) {
            setState(() {
              selectedLength = value!;
            });
          },
          icon: FontAwesomeIcons.ruler,
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
                label: 'Script Type',
                value: selectedScriptType,
                items: scriptTypes,
                onChanged: (value) {
                  setState(() {
                    selectedScriptType = value!;

                    // Auto-select Chapter format for Wattpad or Novel
                    if (value == 'Wattpad' || value == 'Novel') {
                      selectedFormat = 'Chapter';
                      isChapterMode = true;
                    }
                  });
                },
                icon: getScriptTypeIcon(selectedScriptType),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: buildDropdown(
                label: 'Content Format',
                value: selectedFormat,
                items: formatTypes,
                onChanged: (value) {
                  setState(() {
                    selectedFormat = value!;

                    // Enable chapter mode if 'Chapter' is selected
                    if (value == 'Chapter') {
                      isChapterMode = true;
                    }
                  });
                },
                icon: getFormatIcon(selectedFormat),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        // Make Length dropdown full width on desktop
        buildDropdown(
          label: 'Length',
          value: selectedLength,
          items: lengthOptions,
          onChanged: (value) {
            setState(() {
              selectedLength = value!;
            });
          },
          icon: FontAwesomeIcons.ruler,
        ),
      ],
    );
  }

  // Mobile Content Section (Keep original)
  Widget _buildMobileContentSection() {
    return Column(
      children: [
        buildTextField(
          controller: titleController,
          label: 'Title',
          hint: 'Enter a title for your script',
          icon: FontAwesomeIcons.heading,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: genreController,
          label: 'Genre',
          hint: 'E.g., Drama, Comedy, Thriller',
          icon: FontAwesomeIcons.masksTheater, // Changed icon
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: premiseController,
          label: 'Premise/Plot',
          hint: 'Brief description of the story or scene',
          icon: FontAwesomeIcons.lightbulb, // Changed icon
          required: true,
          maxLines: 3,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: charactersController,
          label: 'Characters (Name: Description)',
          hint: 'Alice: Curious, Bob: Grumpy',
          icon: FontAwesomeIcons.users, // Changed icon
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: settingController,
          label: 'Setting',
          hint: 'Where and when the story takes place',
          icon: FontAwesomeIcons.locationDot,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: toneController,
          label: 'Tone/Style (optional)',
          hint: 'E.g., Gritty, Whimsical, Suspenseful',
          icon: FontAwesomeIcons.faceLaughBeam, // Keep tone icon
        ),
      ],
    );
  }

  // Desktop Content Section (Keep original)
  Widget _buildDesktopContentSection() {
    return Column(
      children: [
        buildTextField(
          controller: titleController,
          label: 'Title',
          hint: 'Enter a title for your script',
          icon: FontAwesomeIcons.heading,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: genreController,
          label: 'Genre',
          hint: 'E.g., Drama, Comedy, Thriller',
          icon: FontAwesomeIcons.masksTheater, // Changed icon
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: premiseController,
          label: 'Premise/Plot',
          hint: 'Brief description of the story or scene',
          icon: FontAwesomeIcons.lightbulb, // Changed icon
          required: true,
          maxLines: 3,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: charactersController,
          label: 'Characters (Name: Description)',
          hint: 'Alice: Curious, Bob: Grumpy',
          icon: FontAwesomeIcons.users, // Changed icon
          required: true,
          maxLines: 2,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: settingController,
          label: 'Setting',
          hint: 'Where and when the story takes place',
          icon: FontAwesomeIcons.locationDot,
          required: true,
        ),
        SizedBox(height: 16),
        buildTextField(
          controller: toneController,
          label: 'Tone/Style (optional)',
          hint: 'E.g., Gritty, Whimsical, Suspenseful',
          icon: FontAwesomeIcons.faceLaughBeam, // Keep tone icon
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
                    'Generate Script',
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

  // Desktop Action Button (Modified sizes)
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
                size: 16, // Decreased icon size
              ),
              SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? activeColor : inactiveColor,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                  fontSize: 12, // Decreased font size
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
                      Icon(
                          item == selectedScriptType
                              ? getScriptTypeIcon(item)
                              : item == selectedFormat
                                  ? getFormatIcon(item)
                                  : icon,
                          color: primaryColor,
                          size: 18),
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
        content: Text('Script copied to clipboard'), // Updated message
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
      _isPreparingNewChapter =
          false; // Ensure continuation flag is reset on new generation
      isContinuationPanelVisible = false; // Ensure continuation panel is hidden
      isChapterMode = selectedFormat == 'Chapter' ||
          selectedScriptType == 'Wattpad' ||
          selectedScriptType ==
              'Novel'; // Determine chapter mode for the FIRST generation
      currentChapter = isChapterMode
          ? 1
          : 1; // Reset chapter to 1 for a new generation if in chapter mode
    });

    // Basic validation (Keep original)
    if (titleController.text.trim().isEmpty ||
        genreController.text.trim().isEmpty ||
        premiseController.text.trim().isEmpty ||
        charactersController.text.trim().isEmpty ||
        settingController.text.trim().isEmpty) {
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

        // Add to conversation history
        conversationHistory = [
          {
            'role': 'user',
            'content': prompt,
            'timestamp': DateTime.now().toIso8601String(),
          },
          {
            'role': 'assistant',
            'content': response.trim(),
            'timestamp': DateTime.now().toIso8601String(),
          }
        ];

        // Save to Firebase
        await _saveConversation(isNewConversation: true);

        // Check token limit for future reference
        _checkTokenLimit();

        // Switch to results tab on mobile using the TabControllerMixin helper
        _tabController.navigateToResultsTabIfMobile(context);
      }
    } catch (e) {
      print('Error during API call: $e');
      if (mounted) {
        setState(() {
          isGenerating = false; // Stop generation on error
          _errorMessage = 'Failed to generate content. Please try again later.';
          _isPreparingNewChapter = false; // Reset flag on error too
        });
        showErrorSnackBar('Error during generation. Please try again later.');
      }
    }
  }

  // Build the prompt for the AI API (Keep original)
  String _buildAIPrompt() {
    final String title = titleController.text;
    final String genre = genreController.text;
    final String premise = premiseController.text;
    final String characters = charactersController.text;
    final String setting = settingController.text;
    final String tone = toneController.text;

    // Determine word count based on length
    String wordCountRange;
    switch (selectedLength) {
      case 'Short':
        wordCountRange =
            "approximately 300-500"; // Be specific about word counts
        break;
      case 'Medium':
        wordCountRange = "approximately 500-1000";
        break;
      case 'Long':
        wordCountRange = "approximately 1000-2000";
        break;
      case 'Extended':
        wordCountRange = "approximately 2000-3000";
        break;
      default:
        wordCountRange = "approximately 500-1000"; // Default to medium
    }

    // Base prompt structure
    String basePrompt = '''
You are an expert screenwriter and storyteller. Create a professional script following standard script formatting conventions.

# SCRIPT REQUIREMENTS
*   **Title:** $title
*   **Type:** $selectedScriptType
*   **Format:** $selectedFormat
*   **Genre:** $genre
*   **Length:** $selectedLength ($wordCountRange words)

# CONTENT DETAILS
*   **Premise/Plot:** $premise
*   **Main Characters:** $characters (Ensure descriptions are used to inform character actions and dialogue)
*   **Setting:** $setting (Describe the environment and atmosphere)
*   **Tone/Style:** ${tone.isNotEmpty ? tone : "Determine appropriate tone based on genre and premise"}
''';

    // Add special instructions for Wattpad style
    if (selectedScriptType == 'Wattpad') {
      basePrompt += '''
# WATTPAD STYLE SPECIFIC INSTRUCTIONS
*   Format the story exactly like in a Wattpad novel
*   Use clean paragraph breaks between narrative sections
*   For dialogue, use the format: "- Character line" (with a dash before each spoken line)
*   Example dialogue format:
    - Yes, you're afraid! she interrupted while dropping her glass, which shattered into a thousand pieces on the marble floor.
*   Make sure character emotions and intentions are clear
*   Include descriptive narrative between dialogue sections
*   If this is a chapter, start with "Chapter $currentChapter" or include a chapter title
*   DO NOT use screenplay formatting - use novel style formatting appropriate for Wattpad
''';
    }
    // Standard screenplay formatting for other script types
    else {
      basePrompt += '''
# FORMAT SPECIFICATIONS
*   Follow industry-standard screenplay/script formatting for **$selectedScriptType**.
*   Strictly adhere to formatting rules for **$selectedFormat** (e.g., a scene needs a scene heading, action, and potentially dialogue; dialogue format needs character name centered, dialogue below).
*   Scene Headings: INT./EXT. LOCATION - DAY/NIGHT (or specific time).
*   Action Lines: Present tense, descriptive but concise. Describe what is seen and heard.
*   Character Names: Centered above dialogue, in ALL CAPS initially, then standard casing if needed for action lines.
*   Dialogue: Indented beneath the character name.
*   Parentheticals: Brief, on a separate line, enclosed in parentheses, below character name, before dialogue (use sparingly for tone or brief action).
*   Transitions: (e.g., FADE IN:, FADE OUT., CUT TO:) Right-aligned, in ALL CAPS.
''';
    }

    // Instructions section
    basePrompt += '''
# INSTRUCTIONS
*   Write a compelling ${selectedScriptType == 'Wattpad' ? 'story' : 'script'} based on the provided details.
''';

    // Add specific format instructions
    if (selectedFormat == 'Dialogue' || selectedFormat == 'Monologue') {
      basePrompt +=
          "*   Focus primarily on that element within a basic scene context (minimal action).\n";
    } else if (selectedFormat == 'Action Sequence') {
      basePrompt +=
          "*   Emphasize visual storytelling and action descriptions with minimal dialogue.\n";
    } else if (selectedFormat == 'Full Script') {
      basePrompt +=
          "*   Develop the plot with a clear beginning, middle, and end appropriate for the chosen length.\n";
    } else if (selectedFormat == 'Chapter') {
      basePrompt += '''*   Format as Chapter $currentChapter of a book or novel.
*   Include a chapter heading or title.
*   Ensure the chapter has a clear structure with a beginning, development, and some form of resolution or cliffhanger.
*   Make the chapter feel complete while leaving room for the story to continue.
''';
    }

    // Final instructions
    basePrompt +=
        '''*   Ensure dialogue sounds natural and reflects the characters described.
*   Maintain a consistent tone and style.
*   Output **only** the formatted ${selectedScriptType == 'Wattpad' ? 'story text' : 'script content'}. Do not include explanations, notes, titles unless part of the ${selectedScriptType == 'Wattpad' ? 'story' : 'script'} (like a title page for 'Full Script'), or any text outside the ${selectedScriptType == 'Wattpad' ? 'story' : 'script'} itself.

Generate the $selectedFormat for the $selectedScriptType titled "$title" now:
''';

    return basePrompt;
  }

  // Call to the Groq API Service (Keep original)
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
          padding: EdgeInsets.all(20), // Consistent padding
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
                padding: EdgeInsets.all(12), // Consistent padding
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  FontAwesomeIcons.clapperboard, // Script icon
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
                      'Script Generator', // Consistent title
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18, // Consistent size
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'Create professional scripts and stories', // Consistent tagline
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
        buildSectionHeader('Script Type & Format',
            FontAwesomeIcons.film), // Use consistent icon
        SizedBox(height: 20),
        // Use responsive helpers for dropdowns
        ResponsiveWidget(
          mobile: _buildMobileDropdownSection(),
          desktop: _buildDesktopDropdownSection(),
        ),
        SizedBox(height: 28),

        // Content details section
        buildSectionHeader('Script Content Details',
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

        // Active conversation indicator (if exists)
        if (currentConversationId != null && conversationHistory.isNotEmpty)
          Container(
            margin: EdgeInsets.only(bottom: 16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(
                    isChapterMode
                        ? FontAwesomeIcons.bookOpen
                        : FontAwesomeIcons.clapperboard,
                    color: Colors.teal,
                    size: 18),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isChapterMode
                        ? 'Continuing Chapter Series: ${titleController.text.isNotEmpty ? titleController.text : "Untitled"} (Chapter $currentChapter)'
                        : 'Continuing Series: ${titleController.text.isNotEmpty ? titleController.text : "Untitled"}',
                    style: TextStyle(
                      color: Colors.teal[700],
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                if (isTokenLimitReached)
                  Container(
                    margin: EdgeInsets.only(left: 8),
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber,
                            color: Colors.amber[800], size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Token Limit',
                          style: TextStyle(
                            color: Colors.amber[800],
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                SizedBox(width: 8),
                InkWell(
                  onTap: _startNewConversation,
                  child: Container(
                    padding: EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.teal.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.refresh, color: Colors.teal, size: 16),
                  ),
                ),
              ],
            ),
          ),

        // Generate button
        _buildGenerateButton(), // Use existing helper
      ],
    );
  }
}
