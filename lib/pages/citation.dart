// ignore_for_file: deprecated_member_use, use_build_context_synchronously, avoid_print, prefer_adjacent_string_concatenation, depend_on_referenced_packages
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:sizer/sizer.dart';
import '../models/groq_API.dart';
import '../stripe/paywall.dart';
import '../stripe/stripeinfo.dart';
import '../utils/responsive.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CitationGeneratorPage extends StatefulWidget {
  const CitationGeneratorPage({super.key});

  @override
  State<CitationGeneratorPage> createState() => _CitationGeneratorPageState();
}

class _CitationGeneratorPageState extends State<CitationGeneratorPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _searchResults = [];
  final List<Map<String, dynamic>> _generatedCitations = [];
  bool _isLoading = false;
  late AnimationController _animationController;
  final ScrollController _scrollController = ScrollController();
  String? _errorMessage;
  final _groqApiKey = dotjsonenv.env['_groqApiKey'] ?? "";
  late GroqApiService _groqApiService;

  // Variables pour la vérification de l'abonnement
  String? userSubscriptionPlan;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  bool _isTrialActive = false;
  DateTime? _trialEndDate;
  bool _isSubscribed = false;
  bool _isSubscriptionLoading = true;
  String? customerId;
  bool _isBusinessTrial =
      false; // Variable pour suivre si l'essai est pour le plan Business

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _groqApiService = GroqApiService(apiKey: _groqApiKey);
    _checkUserSubscription();
    _checkSubscriptionStatus();
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
      final data = subscriptions['data'] as List;
      final activeSubscriptions = data.where(
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

            // Vérifier si l'essai est pour le plan Business
            final productName = await _fetchProductName(productId);
            _isBusinessTrial = productName == 'Business';
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

      if (productName.contains('standard')) {
        return 'standard';
      } else if (productName.contains('Pro')) {
        return 'pro';
      } else if (productName.contains('Business')) {
        return 'business';
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
        // Mettre à jour l'état d'abonnement
        _isSubscribed = plan != null;
      });
    }
  }

  // Vérifie si l'utilisateur a un plan Business actif
  bool get _isBusinessUser {
    return userSubscriptionPlan == 'Business';
  }

  // Vérifie si l'utilisateur peut utiliser la fonctionnalité (soit plan Business, soit en essai Business)
  bool get _canUseFeature {
    return _isBusinessUser || (_isTrialActive && _isBusinessTrial);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Appel à l'API Groq à l'aide du nouveau service
  Future<String> _callGroqAPI(String prompt) async {
    if (!_canUseFeature) {
      throw Exception(
          'Access denied: This feature requires a Business subscription');
    }

    try {
      return await _groqApiService.generateContent(prompt);
    } catch (e) {
      throw Exception('Groq API error: $e');
    }
  }

  Future<void> _searchCitations() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = "Please enter a search term";
      });
      return;
    }

    // Vérification d'accès - vérifie les utilisateurs Business et les essais Business
    if (!_canUseFeature) {
      setState(() {
        _errorMessage =
            "This feature is exclusively available to Business users. Please upgrade your plan.";
      });
      _showUpgradeDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final String query = _searchController.text;

    try {
      String prompt = 'generate strictly in the language of the question ' +
          'Generate 50 new citations entries related to "$query" in movies, manga, school, science and books format. ' +
          'Include title, authors, year, and journal/book information. ' +
          'Format each citation as a separate paragraph with title on first line, ' +
          'authors on second line, year on third line, and source on fourth line.';

      final responseText = await _callGroqAPI(prompt);

      final List<String> citations = responseText.split('\n\n');
      _searchResults = citations
          .map((citation) {
            final parts = citation.split('\n');
            if (parts.isEmpty) {
              return {'title': '', 'authors': '', 'year': '', 'source': ''};
            }

            return {
              'title': parts[0].replaceAll(RegExp(r'^\d+\.\s*'), ''),
              'authors': parts.length > 1 ? parts[1] : '',
              'year': parts.length > 2 ? parts[2] : '',
              'source': parts.length > 3 ? parts[3] : '',
            };
          })
          .where((map) => map['title']!.isNotEmpty)
          .toList();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('Error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "An error occurred. Please try again.";
        _searchResults = [];
      });
    }
  }

  Future<void> _generateCitation(Map<String, String> citation) async {
    // Vérification d'accès - vérifie les utilisateurs Business et les essais Business
    if (!_canUseFeature) {
      setState(() {
        _errorMessage =
            "This feature is exclusively available to Business users. Please upgrade your plan.";
      });
      _showUpgradeDialog();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String prompt = 'Generate strictly in the language of the request ' +
          'Generate 1 unique new citation based on this information: ${citation['title']} by ${citation['authors']} (${citation['year']}). ' +
          'Make it creative, mid-long and inspiring. Base it only on those informations but don\'t include them in the citation. ' +
          'Format the citation with quotes like this: ❞citation text here❞';

      final responseText = await _callGroqAPI(prompt);

      // Extract just the quote part if possible
      final quoteRegex = RegExp(r'❞([^❞]+)❞');
      final match = quoteRegex.firstMatch(responseText);
      final finalText =
          match != null ? '❞${match.group(1)}❞' : responseText.trim();

      setState(() {
        _generatedCitations.add({
          'text': finalText,
          'isEditing': false,
          'controller': TextEditingController(text: finalText),
          'source': '${citation['title']} (${citation['year']})',
        });
        _isLoading = false;
        _searchResults = [];
        _searchController.clear();
      });

      _animationController.forward(from: 0);
      _scrollToBottom();
    } catch (e) {
      print('Error: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = "Failed to generate citation. Please try again.";
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _toggleEdit(int index) {
    setState(() {
      _generatedCitations[index]['isEditing'] =
          !_generatedCitations[index]['isEditing'];
      if (!_generatedCitations[index]['isEditing']) {
        _generatedCitations[index]['text'] =
            _generatedCitations[index]['controller'].text;
      }
    });
  }

  void _saveCitation(int index) {
    setState(() {
      _generatedCitations[index]['text'] =
          _generatedCitations[index]['controller'].text;
      _generatedCitations[index]['isEditing'] = false;
    });

    // Show a more elegant snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 16),
            const Text('Citation saved successfully'),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: 10,
          right: 10,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _copyCitation(int index) {
    Clipboard.setData(ClipboardData(text: _generatedCitations[index]['text']));

    // Show a more elegant snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.copy, color: Colors.white),
            const SizedBox(width: 16),
            const Text('Citation copied to clipboard'),
          ],
        ),
        backgroundColor: Colors.blue.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.only(
          bottom: MediaQuery.of(context).size.height - 100,
          left: 10,
          right: 10,
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _deleteCitation(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Citation'),
          content: const Text('Are you sure you want to delete this citation?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.black)),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _generatedCitations.removeAt(index);
                });
                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Row(
                      children: [
                        const Icon(Icons.delete, color: Colors.white),
                        const SizedBox(width: 16),
                        const Text('Citation deleted'),
                      ],
                    ),
                    backgroundColor: Colors.red.shade700,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    margin: EdgeInsets.only(
                      bottom: MediaQuery.of(context).size.height - 100,
                      left: 10,
                      right: 10,
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  // Vérification de l'état de l'abonnement
  Future<void> _checkSubscriptionStatus() async {
    setState(() {
      _isSubscriptionLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        // Gestion plus sécurisée des données potentiellement nulles ou manquantes
        if (userData.exists) {
          final data = userData.data() as Map<String, dynamic>?;
          if (data != null && data.containsKey('customerId')) {
            customerId = data['customerId'] as String?;
          } else {
            customerId = null;
          }
        } else {
          customerId = null;
        }
      } else {
        customerId = null;
      }

      if (customerId != null && customerId!.isNotEmpty) {
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

          if (subscriptions.containsKey('data') &&
              subscriptions['data'] is List) {
            final subsList = subscriptions['data'] as List;
            final activeSubscriptions = subsList
                .where((sub) => sub is Map && sub['status'] == 'active')
                .toList();
            final trialSubscriptions = subsList
                .where((sub) => sub is Map && sub['status'] == 'trialing')
                .toList();

            // Mettre à jour l'état de l'essai si nécessaire
            if (trialSubscriptions.isNotEmpty) {
              final subscription = trialSubscriptions.first;
              final trialEnd = subscription['trial_end'];
              final productId = subscription['plan']['product'];

              if (trialEnd != null) {
                _trialEndDate =
                    DateTime.fromMillisecondsSinceEpoch(trialEnd * 1000);
                _isTrialActive = true;

                // Vérifier si l'essai est pour le plan Business
                final productName = await _fetchProductName(productId);
                _isBusinessTrial = productName == 'business';
              }
            }

            setState(() {
              _isSubscribed = activeSubscriptions.isNotEmpty ||
                  trialSubscriptions.isNotEmpty;
            });
          } else {
            print('Format de réponse Stripe inattendu: ${response.body}');
            setState(() {
              _isSubscribed = false;
            });
          }
        } else {
          print('Erreur API Stripe: ${response.statusCode} ${response.body}');
          setState(() {
            _isSubscribed = false;
          });
        }
      } else {
        setState(() {
          _isSubscribed = false;
        });
      }
    } catch (e) {
      print('Erreur lors de la vérification de l\'abonnement: $e');
      setState(() {
        _isSubscribed = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubscriptionLoading = false;
        });
      }
    }
  }

  // Navigation vers l'écran d'abonnement
  Future<void> _handleSubscriptionNavigation() async {
    if (_isSubscriptionLoading) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Dialog(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text("loading...")
                ],
              ),
            ),
          );
        },
      );

      try {
        await Future.doWhile(() => Future.delayed(
            const Duration(milliseconds: 100),
            () => _isSubscriptionLoading)).timeout(const Duration(seconds: 10));
      } catch (e) {
        print(
            "Délai d'attente dépassé lors de la vérification de l'abonnement: $e");
      }

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    if (!context.mounted) return;

    if (_isSubscribed) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionInfoPage(),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const SubscriptionBottomSheet(),
        ),
      );
    }
  }

  // Afficher la boîte de dialogue d'upgrade
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
            width: MediaQuery.of(context).size.width * 0.8,
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.workspace_premium,
                          color: Colors.white, size: 28),
                      SizedBox(width: 15),
                      Text(
                        'Upgrade to Business Plan',
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
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'This feature is exclusively available to Business plan users.',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          fontFamily: 'Courier',
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
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
                            onPressed: () {
                              Navigator.of(context).pop();
                              _handleSubscriptionNavigation();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 3,
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.upgrade,
                                  color: Colors.white,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Upgrade Now',
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

  Widget _buildSearchBox() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TextField(
        maxLines: null,
        controller: _searchController,
        style: const TextStyle(fontFamily: 'Courier', fontSize: 12),
        decoration: InputDecoration(
          hintText: 'Search by keyword (e.g., "leadership", "innovation")',
          hintStyle: const TextStyle(
            fontFamily: 'Courier',
            color: Colors.black,
          ),
          prefixIcon: const Icon(Icons.search, color: Colors.black54),
          suffixIcon: Container(
            margin: const EdgeInsets.all(5),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 15),
              ),
              onPressed: _canUseFeature ? _searchCitations : _showUpgradeDialog,
              child: const Text(
                'Search',
                style: TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 14,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: const BorderSide(color: Colors.black, width: 1),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        ),
        onSubmitted: (_) =>
            _canUseFeature ? _searchCitations() : _showUpgradeDialog(),
      ),
    );
  }

  Widget _buildCitationCard(Map<String, dynamic> citationData, int index) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.15),
            spreadRadius: 2,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Citation ${index + 1}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                  color: Colors.black87,
                ),
              ),
              Row(
                children: [
                  if (!citationData['isEditing'])
                    IconButton(
                      icon:
                          const Icon(Icons.copy, color: Colors.black, size: 20),
                      onPressed: () => _copyCitation(index),
                      tooltip: 'Copy citation',
                    ),
                  IconButton(
                    icon: Icon(
                      citationData['isEditing'] ? Icons.close : Icons.edit,
                      color:
                          citationData['isEditing'] ? Colors.red : Colors.black,
                      size: 20,
                    ),
                    onPressed: () => _toggleEdit(index),
                    tooltip: citationData['isEditing']
                        ? 'Cancel editing'
                        : 'Edit citation',
                  ),
                  if (citationData['isEditing'])
                    IconButton(
                      icon:
                          const Icon(Icons.save, color: Colors.black, size: 20),
                      onPressed: () => _saveCitation(index),
                      tooltip: 'Save citation',
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.delete,
                          color: Colors.black, size: 20),
                      onPressed: () => _deleteCitation(index),
                      tooltip: 'Delete citation',
                    ),
                ],
              ),
            ],
          ),
          const Divider(thickness: 1),
          if (citationData['source'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Source: ${citationData['source']}',
                style: TextStyle(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade700,
                  fontFamily: 'Courier',
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (citationData['isEditing'])
            TextField(
              controller: citationData['controller'],
              maxLines: null,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 16,
                height: 1.5,
              ),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.black, width: 1),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
                contentPadding: const EdgeInsets.all(16),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200, width: 1),
              ),
              child: Text(
                citationData['text'],
                style: const TextStyle(
                  fontSize: 16,
                  fontFamily: 'Courier',
                  height: 1.5,
                  letterSpacing: 0.3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Résultats de recherche avant citation finale
  Widget _buildSearchResultCard(Map<String, String> citation) {
    return Card(
      elevation: 3,
      color: Colors.white,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            _canUseFeature ? _generateCitation(citation) : _showUpgradeDialog(),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                citation['title'] ?? '',
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                citation['authors'] ?? '',
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    citation['year'] ?? '',
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 11,
                      color: Colors.black54,
                    ),
                  ),
                  Text(
                    'Tap to generate',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 10,
                      color: Colors.blue.shade700,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                citation['source'] ?? '',
                style: const TextStyle(
                  fontFamily: 'Courier',
                  fontSize: 11,
                  color: Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        const Text(
          '❞Citation❞',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: const Text(
            'Instantly create, edit, and save citations in over 50 different styles',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontFamily: 'Courier',
              color: Colors.black87,
              height: 1.5,
            ),
          ),
        ),

        // Badge d'accès Business ou Essai Business
        if (_canUseFeature) // Utilisation de la variable _canUseFeature
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.stars, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Text(
                  _isBusinessUser ? 'Business Plan -' : 'Business Trial -',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
                // Afficher un badge de période d'essai si applicable
                if (_isTrialActive && !_isBusinessUser && _trialEndDate != null)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange),
                    ),
                    child: Text(
                      'Trial ends: ${_trialEndDate!.day}/${_trialEndDate!.month}/${_trialEndDate!.year}',
                      style: TextStyle(
                        color: Colors.orange[800],
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          )
        // Badge d'accès restreint (non Business)
        else
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock, color: Colors.red[800], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Business Plan Required',
                  style: TextStyle(
                    color: Colors.red[800],
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _handleSubscriptionNavigation,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[800],
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: const Size(0, 0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text(
                    'Upgrade',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ResponsiveWidget(
      mobile: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: SingleChildScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 32),
                    _buildSearchBox(),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontFamily: 'Courier',
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    if (_isLoading)
                      Center(
                        child: Column(
                          children: [
                            LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.black,
                              size: 40,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Generating content...',
                              style: TextStyle(
                                fontFamily: 'Courier',
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (_searchResults.isNotEmpty && _canUseFeature)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 8.0, bottom: 16.0),
                            child: Text(
                              'Search Results (${_searchResults.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                          ListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _searchResults.length,
                            itemBuilder: (context, index) {
                              return _buildSearchResultCard(
                                  _searchResults[index]);
                            },
                          ),
                        ],
                      ),
                    if (_generatedCitations.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 8.0, top: 5.0, bottom: 8.0),
                            child: Text(
                              'Your Citations (${_generatedCitations.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                          ..._generatedCitations.asMap().entries.map((entry) {
                            return _buildCitationCard(entry.value, entry.key);
                          }),
                        ],
                      ),
                    SizedBox(height: 10.h),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),

      // Version DESKTOP
      desktop: Padding(
        padding: const EdgeInsets.all(30.0),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildHeader(),
                          const SizedBox(height: 40),
                          SizedBox(
                            width: 70.w,
                            child: _buildSearchBox(),
                          ),
                          if (_errorMessage != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 16.0),
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ),
                          const SizedBox(height: 40),
                          if (_isLoading)
                            Center(
                              child: Column(
                                children: [
                                  LoadingAnimationWidget.staggeredDotsWave(
                                    color: Colors.black,
                                    size: 50,
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Generating content...',
                                    style: TextStyle(
                                      fontFamily: 'Courier',
                                      fontSize: 16,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else if (_searchResults.isNotEmpty && _canUseFeature)
                            Container(
                              width: 70.w,
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Search Results (${_searchResults.length})',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 10),
                                  GridView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      childAspectRatio: 2.5,
                                      crossAxisSpacing: 20,
                                      mainAxisSpacing: 20,
                                    ),
                                    itemCount: _searchResults.length,
                                    itemBuilder: (context, index) {
                                      return _buildSearchResultCard(
                                          _searchResults[index]);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          if (_generatedCitations.isNotEmpty)
                            Container(
                              width: 70.w,
                              margin: const EdgeInsets.only(top: 40),
                              padding: const EdgeInsets.all(30),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.grey.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your Citations (${_generatedCitations.length})',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Divider(),
                                  const SizedBox(height: 20),
                                  ..._generatedCitations
                                      .asMap()
                                      .entries
                                      .map((entry) {
                                    return _buildCitationCard(
                                        entry.value, entry.key);
                                  }),
                                ],
                              ),
                            ),
                          SizedBox(height: 10.h),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
