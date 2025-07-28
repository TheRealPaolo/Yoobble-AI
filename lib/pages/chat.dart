// ignore_for_file: avoid_print, use_build_context_synchronously, deprecated_member_use
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:image_picker/image_picker.dart';
import 'package:universal_html/html.dart' as html;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sizer/sizer.dart';
import 'package:http/http.dart' as http;
import '../models/chat.dart';
import '../models/groq_API.dart';
import '../models/quotas.dart';
import '../stripe/paywall.dart';
import '../stripe/stripeinfo.dart';

class AIPersonalityConfig extends StatefulWidget {
  final VoidCallback onConfigComplete;

  const AIPersonalityConfig({super.key, required this.onConfigComplete});

  @override
  State<AIPersonalityConfig> createState() => _AIPersonalityConfigState();
}

class _AIPersonalityConfigState extends State<AIPersonalityConfig> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _personalityController = TextEditingController();
  final TextEditingController _interestsController = TextEditingController();
  final TextEditingController _communicationStyleController =
      TextEditingController();
  String _selectedLanguage = 'English';
  String? _profileImageBase64;
  Uint8List? _profileImageBytes;
  bool _isLoading = false;
  int _currentStep = 0;
  User? _currentUser;

  final List<String> _languages = [
    'English',
    'French',
    'Spanish',
    'German',
    'Italian',
    'Portuguese',
    'Chinese',
    'Japanese',
    'Korean',
    'Russian',
    'Arabic'
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _checkExistingConfig();
  }

  void _getCurrentUser() {
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  Future<void> _checkExistingConfig() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        // Check Firestore for existing configuration
        final docSnapshot = await FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid)
            .get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          setState(() {
            _nameController.text = data['name'] ?? '';
            _personalityController.text = data['personality'] ?? '';
            _interestsController.text = data['interests'] ?? '';
            _communicationStyleController.text =
                data['communicationStyle'] ?? '';
            _selectedLanguage = data['language'] ?? 'English';
            _profileImageBase64 = data['profileImage'];

            if (_profileImageBase64 != null) {
              _profileImageBytes = base64Decode(_profileImageBase64!);
            }
          });
        }
      }
    } catch (e) {
      print('Error loading configuration: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        // Web implementation
        final html.FileUploadInputElement input = html.FileUploadInputElement();
        input.accept = 'image/*';
        input.click();

        await input.onChange.first;
        if (input.files != null && input.files!.isNotEmpty) {
          final file = input.files![0];
          final reader = html.FileReader();
          reader.readAsDataUrl(file);

          await reader.onLoad.first;
          final result = reader.result as String;
          final base64Image = result.split(',')[1];

          setState(() {
            _profileImageBytes = base64Decode(base64Image);
            _profileImageBase64 = base64Image;
          });
        }
      } else {
        // Mobile implementation
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 80,
        );

        if (image != null) {
          final bytes = await image.readAsBytes();
          final base64Image = base64Encode(bytes);

          setState(() {
            _profileImageBytes = bytes;
            _profileImageBase64 = base64Image;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        // Save to Firestore
        await FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid)
            .set({
          'name': _nameController.text,
          'personality': _personalityController.text,
          'interests': _interestsController.text,
          'communicationStyle': _communicationStyleController.text,
          'language': _selectedLanguage,
          'profileImage': _profileImageBase64,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'userId': _currentUser!.uid, // Add user ID to link configuration
        });

        // Save configuration status to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('ai_configured', true);

        // Call the callback to notify parent
        widget.onConfigComplete();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving configuration: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _nextStep() {
    if (_currentStep < 4) {
      setState(() {
        _currentStep += 1;
      });
    } else {
      _saveConfiguration();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep -= 1;
      });
    }
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(5, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4.0),
            height: 8,
            width: _currentStep == index ? 24 : 8,
            decoration: BoxDecoration(
              color: _currentStep >= index ? Colors.blue : Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return _buildBasicInfoStep();
      case 1:
        return _buildPersonalityStep();
      case 2:
        return _buildInterestsStep();
      case 3:
        return _buildCommunicationStyleStep();
      case 4:
        return _buildReviewStep();
      default:
        return Container();
    }
  }

  Widget _buildBasicInfoStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Basic Information',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Let\'s start by setting up the basics for your AI companion.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 40),
        Center(
          child: GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.grey[200],
                  backgroundImage: _profileImageBytes != null
                      ? MemoryImage(_profileImageBytes!)
                      : null,
                  child: _profileImageBytes == null
                      ? Icon(
                          Icons.person,
                          size: 80,
                          color: Colors.grey[400],
                        )
                      : null,
                ),
                Positioned(
                  right: 5,
                  bottom: 5,
                  child: Container(
                    padding: EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 5,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.add_a_photo,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 32),
        TextFormField(
          controller: _nameController,
          decoration: InputDecoration(
            labelText: 'Name your AI companion',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: Icon(Icons.badge),
            fillColor: Colors.white,
            filled: true,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter a name';
            }
            return null;
          },
        ),
        SizedBox(height: 24),
        DropdownButtonFormField<String>(
          value: _selectedLanguage,
          decoration: InputDecoration(
            labelText: 'Preferred Language',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            prefixIcon: Icon(Icons.language),
            fillColor: Colors.white,
            filled: true,
          ),
          items: _languages.map((String language) {
            return DropdownMenuItem<String>(
              value: language,
              child: Text(language),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedLanguage = newValue;
              });
            }
          },
        ),
      ],
    );
  }

  Widget _buildPersonalityStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personality',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Describe the personality traits you want your AI to have.',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 32),
        TextFormField(
          controller: _personalityController,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: 'Personality Traits',
            hintText: 'Example: friendly, humorous, analytical, empathetic...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            alignLabelWithHint: true,
            fillColor: Colors.white,
            filled: true,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please describe your AI\'s personality';
            }
            return null;
          },
        ),
        SizedBox(height: 24),
        Card(
          elevation: 2,
          color: Colors.blue[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lightbulb, color: Colors.amber, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Tips',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Be specific about personality traits like "patient and detailed when explaining complex topics" or "concise and direct with information".',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInterestsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Interests & Knowledge',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'What topics or areas of knowledge should your AI be particularly good at?',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 32),
        TextFormField(
          controller: _interestsController,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: 'Interests & Expertise Areas',
            hintText:
                'Example: technology, science, cooking, fitness, history...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            alignLabelWithHint: true,
            fillColor: Colors.white,
            filled: true,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please enter some interests or knowledge areas';
            }
            return null;
          },
        ),
        SizedBox(height: 24),
        Card(
          elevation: 2,
          color: Colors.green[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.psychology, color: Colors.green, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Why This Matters',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  'Your AI will be tailored to be more knowledgeable and enthusiastic about these topics, making conversations more engaging and helpful.',
                  style: TextStyle(
                    fontSize: 16,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCommunicationStyleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Communication Style',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'How would you like your AI to communicate with you?',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 32),
        TextFormField(
          controller: _communicationStyleController,
          maxLines: 7,
          decoration: InputDecoration(
            labelText: 'Communication Style',
            hintText:
                'Example: casual and conversational, formal and professional, brief and to-the-point...',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            alignLabelWithHint: true,
            fillColor: Colors.white,
            filled: true,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Please describe your preferred communication style';
            }
            return null;
          },
        ),
        SizedBox(height: 24),
        Card(
          elevation: 2,
          color: Colors.purple[50],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.chat_bubble, color: Colors.purple, size: 28),
                    SizedBox(width: 12),
                    Text(
                      'Communication Examples',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 12),
                Text(
                  "• Casual: Hey! I think that's a great idea. Want to try it?",
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                SizedBox(height: 8),
                Text(
                  '• Formal: "I concur with your assessment. Would you like to proceed?"',
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
                SizedBox(height: 8),
                Text(
                  "• Direct: Good idea. Let's do it.",
                  style: TextStyle(fontSize: 16, height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Review Your Settings',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 12),
          Text(
            'Here\'s a summary of your AI companion\'s configuration.',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[700],
            ),
          ),
          SizedBox(height: 32),
          Center(
            child: CircleAvatar(
              radius: 70,
              backgroundColor: Colors.grey[200],
              backgroundImage: _profileImageBytes != null
                  ? MemoryImage(_profileImageBytes!)
                  : null,
              child: _profileImageBytes == null
                  ? Icon(
                      Icons.person,
                      size: 70,
                      color: Colors.grey[400],
                    )
                  : null,
            ),
          ),
          SizedBox(height: 32),
          _buildReviewItem('Name', _nameController.text),
          _buildReviewItem('Language', _selectedLanguage),
          _buildReviewItem('Personality', _personalityController.text),
          _buildReviewItem('Interests & Expertise', _interestsController.text),
          _buildReviewItem(
              'Communication Style', _communicationStyleController.text),
          SizedBox(height: 24),
          Card(
            elevation: 2,
            color: Colors.amber[50],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.amber, size: 28),
                      SizedBox(width: 12),
                      Text(
                        'Note',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    'You can always modify these settings later from your profile settings.',
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.5,
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

  Widget _buildReviewItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey[800],
            ),
          ),
          SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 4,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 16, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive width for better desktop layout
    double containerWidth = MediaQuery.of(context).size.width;
    containerWidth = containerWidth > 1200
        ? 800
        : (containerWidth > 800 ? containerWidth * 0.7 : containerWidth - 40);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(),
              )
            : Form(
                key: _formKey,
                child: Center(
                  child: Container(
                    width: containerWidth,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                    child: Column(
                      children: [
                        _buildStepIndicator(),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16.0),
                              child: _buildStepContent(),
                            ),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 16.0, top: 16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              if (_currentStep > 0)
                                ElevatedButton(
                                  onPressed: _previousStep,
                                  style: ElevatedButton.styleFrom(
                                    foregroundColor: Colors.black,
                                    backgroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 32, vertical: 16),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      side:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    'Back',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                )
                              else
                                SizedBox(width: 0),
                              ElevatedButton(
                                onPressed: _currentStep == 4
                                    ? _saveConfiguration
                                    : _nextStep,
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.blue,
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 32, vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 2,
                                ),
                                child: Text(
                                  _currentStep == 4 ? 'Complete Setup' : 'Next',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
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

/////////////////////// New settings page to modify AI configuration later/////////////////////////////////////////////////////////

class AIPersonalitySettings extends StatefulWidget {
  const AIPersonalitySettings({super.key});

  @override
  State<AIPersonalitySettings> createState() => _AIPersonalitySettingsState();
}

class _AIPersonalitySettingsState extends State<AIPersonalitySettings> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _personalityController = TextEditingController();
  final TextEditingController _interestsController = TextEditingController();
  final TextEditingController _communicationStyleController =
      TextEditingController();
  String _selectedLanguage = 'English';
  String? _profileImageBase64;
  Uint8List? _profileImageBytes;
  bool _isLoading = false;
  User? _currentUser;
  bool _hasChanges = false;

  final List<String> _languages = [
    'English',
    'French',
    'Spanish',
    'German',
    'Italian',
    'Portuguese',
    'Chinese',
    'Japanese',
    'Korean',
    'Russian',
    'Arabic'
  ];

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
    _loadConfiguration();
  }

  void _getCurrentUser() {
    _currentUser = FirebaseAuth.instance.currentUser;
  }

  Future<void> _loadConfiguration() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid)
            .get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          setState(() {
            _nameController.text = data['name'] ?? '';
            _personalityController.text = data['personality'] ?? '';
            _interestsController.text = data['interests'] ?? '';
            _communicationStyleController.text =
                data['communicationStyle'] ?? '';
            _selectedLanguage = data['language'] ?? 'English';
            _profileImageBase64 = data['profileImage'];

            if (_profileImageBase64 != null) {
              _profileImageBytes = base64Decode(_profileImageBase64!);
            }
          });
        }
      }
    } catch (e) {
      print('Error loading configuration: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }

    // Listen for changes in form fields
    _nameController.addListener(_checkForChanges);
    _personalityController.addListener(_checkForChanges);
    _interestsController.addListener(_checkForChanges);
    _communicationStyleController.addListener(_checkForChanges);
  }

  void _checkForChanges() {
    setState(() {
      _hasChanges = true;
    });
  }

  Future<void> _pickImage() async {
    try {
      if (kIsWeb) {
        // Web implementation
        final html.FileUploadInputElement input = html.FileUploadInputElement();
        input.accept = 'image/*';
        input.click();

        await input.onChange.first;
        if (input.files != null && input.files!.isNotEmpty) {
          final file = input.files![0];
          final reader = html.FileReader();
          reader.readAsDataUrl(file);

          await reader.onLoad.first;
          final result = reader.result as String;
          final base64Image = result.split(',')[1];

          setState(() {
            _profileImageBytes = base64Decode(base64Image);
            _profileImageBase64 = base64Image;
            _hasChanges = true;
          });
        }
      } else {
        // Mobile implementation
        final ImagePicker picker = ImagePicker();
        final XFile? image = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 600,
          maxHeight: 600,
          imageQuality: 80,
        );

        if (image != null) {
          final bytes = await image.readAsBytes();
          final base64Image = base64Encode(bytes);

          setState(() {
            _profileImageBytes = bytes;
            _profileImageBase64 = base64Image;
            _hasChanges = true;
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error selecting image: $e')),
      );
    }
  }

  Future<void> saveAIPersonalitySettings(
      String userId, Map<String, dynamic> settings) async {
    try {
      // Référence à la collection et au document
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('settings')
          .doc('ai_personality');

      // Vérifier si le document existe
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        // Mettre à jour le document existant
        await docRef.update(settings);
      } else {
        // Créer un nouveau document
        await docRef.set(settings);
      }
    } catch (e) {
      debugPrint('Erreur lors de la sauvegarde des paramètres: $e');
      throw Exception('Échec de la sauvegarde des paramètres');
    }
  }

  Future<void> _saveConfiguration() async {
    if (!_formKey.currentState!.validate()) return;

    // Check if required fields are filled
    if (_nameController.text.trim().isEmpty ||
        _personalityController.text.trim().isEmpty ||
        _interestsController.text.trim().isEmpty ||
        _communicationStyleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill all required fields'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        // Préparer les données à sauvegarder
        final data = {
          'name': _nameController.text,
          'personality': _personalityController.text,
          'interests': _interestsController.text,
          'communicationStyle': _communicationStyleController.text,
          'language': _selectedLanguage,
          'profileImage': _profileImageBase64,
          'updatedAt': FieldValue.serverTimestamp(),
          'userId': _currentUser!.uid,
        };

        // Référence au document
        final docRef = FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid);

        // Vérifier si le document existe
        final docSnapshot = await docRef.get();

        if (docSnapshot.exists) {
          // Mettre à jour le document existant
          await docRef.update(data);
        } else {
          // Créer un nouveau document
          await docRef.set(data);
        }

        setState(() {
          _hasChanges = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('AI personality settings updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving configuration: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // Clean up listeners
    _nameController.removeListener(_checkForChanges);
    _personalityController.removeListener(_checkForChanges);
    _interestsController.removeListener(_checkForChanges);
    _communicationStyleController.removeListener(_checkForChanges);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate responsive width for better desktop layout
    double containerWidth = MediaQuery.of(context).size.width;
    containerWidth = containerWidth > 1200
        ? 800
        : (containerWidth > 800 ? containerWidth * 0.7 : containerWidth);

    return Scaffold(
      backgroundColor: Colors.white,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(),
            )
          : Form(
              key: _formKey,
              child: Center(
                child: Container(
                  width: containerWidth,
                  padding: EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Image Section
                        Center(
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickImage,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 80,
                                      backgroundColor: Colors.grey[200],
                                      backgroundImage:
                                          _profileImageBytes != null
                                              ? MemoryImage(_profileImageBytes!)
                                              : null,
                                      child: _profileImageBytes == null
                                          ? Icon(
                                              Icons.person,
                                              size: 80,
                                              color: Colors.grey[400],
                                            )
                                          : null,
                                    ),
                                    Positioned(
                                      right: 5,
                                      bottom: 5,
                                      child: Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 5,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.add_a_photo,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: 12),
                              Text(
                                'AI Avatar',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 40),

                        // Name and Language Section
                        Text(
                          'Basic Information',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'AI Name',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.badge),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter a name';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 20),
                        DropdownButtonFormField<String>(
                          value: _selectedLanguage,
                          decoration: InputDecoration(
                            labelText: 'Preferred Language',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: Icon(Icons.language),
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          items: _languages.map((String language) {
                            return DropdownMenuItem<String>(
                              value: language,
                              child: Text(language),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedLanguage = newValue;
                                _hasChanges = true;
                              });
                            }
                          },
                        ),
                        SizedBox(height: 40),

                        // Personality Section
                        Text(
                          'Personality',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _personalityController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Personality Traits',
                            hintText:
                                'Example: friendly, humorous, analytical...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignLabelWithHint: true,
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please describe your AI\'s personality';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 40),

                        // Interests Section
                        Text(
                          'Interests & Knowledge',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _interestsController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Interests & Expertise Areas',
                            hintText:
                                'Example: technology, science, cooking...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignLabelWithHint: true,
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter some interests or knowledge areas';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 40),

                        // Communication Style Section
                        Text(
                          'Communication Style',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: _communicationStyleController,
                          maxLines: 5,
                          decoration: InputDecoration(
                            labelText: 'Communication Style',
                            hintText: 'Example: casual, formal, direct...',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignLabelWithHint: true,
                            fillColor: Colors.white,
                            filled: true,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please describe your preferred communication style';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: 40),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: ElevatedButton(
                            onPressed: _hasChanges ? _saveConfiguration : null,
                            style: ElevatedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.blue,
                              disabledBackgroundColor: Colors.grey[300],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 2,
                            ),
                            child: Text(
                              'Save Changes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// Updated Chat Screen to integrate with AI personality ///////////////////////////////////////////////////////////////////////////////////////
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final List<Message> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final _groqApiKey = dotjsonenv.env['_groqApiKey'] ?? "";
  bool _isLoading = false;
  User? _currentUser;
  String? _selectedImageBase64;
  Uint8List? _selectedImageBytes;
  late GroqApiService _groqApiService;

  // AI Configuration fields
  String? _aiName;
  String? _aiPersonality;
  String? _aiInterests;
  String? _aiCommunicationStyle;
  String? _aiLanguage;
  String? _aiProfileImageBase64;
  bool _isAiConfigured = false;
  bool _isCheckingConfig = true;

  // Instance du gestionnaire de quotas
  final ApiQuotaManager _quotaManager = ApiQuotaManager();
  int _remainingQuota = 0;
  int _totalDailyLimit = ApiQuotaManager.dailyLimit;
  bool _isLoadingQuota = true;

  // Variables pour la vérification de l'abonnement
  String? userSubscriptionPlan;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  bool _isTrialActive = false;
  bool _isSubscribed = false;
  bool _isSubscriptionLoading = true;
  String? customerId;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // Méthode principale d'initialisation avec une séquence d'exécution claire
  Future<void> _initializeApp() async {
    try {
      _getCurrentUser();
      _groqApiService = GroqApiService(apiKey: _groqApiKey);

      // Étape 1: Vérifier et charger la configuration IA
      await _checkAiConfiguration();

      // Étape 2: Charger les messages précédents
      await _loadMessages();

      // Étape 3: Vérifier le statut d'abonnement et les quotas
      await _checkSubscriptionStatus();

      // Étape 4: Charger les quotas disponibles basés sur l'abonnement
      await _loadRemainingQuota();
    } catch (e) {
      print('Error initializing app: $e');
      // Gérer l'initialisation échouée - peut-être afficher un message d'erreur
      setState(() {
        _isCheckingConfig = false;
        _isLoadingQuota = false;
        _isSubscriptionLoading = false;
      });
    }
  }

  void _getCurrentUser() {
    _currentUser = FirebaseAuth.instance.currentUser;
    setState(() {});
  }

  Future<void> _checkAiConfiguration() async {
    setState(() {
      _isCheckingConfig = true;
    });

    try {
      if (_currentUser != null) {
        // First check if user already has a config in Firestore
        final docSnapshot = await FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid)
            .get();

        if (docSnapshot.exists) {
          // Config exists in Firestore, load it and update shared prefs
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('ai_configured', true);

          await _loadAiConfiguration();
          setState(() {
            _isAiConfigured = true;
          });
        } else {
          // Check SharedPreferences as fallback
          final prefs = await SharedPreferences.getInstance();
          final configured = prefs.getBool('ai_configured') ?? false;

          setState(() {
            _isAiConfigured = configured;
          });

          if (configured) {
            await _loadAiConfiguration();
          }
        }
      } else {
        setState(() {
          _isAiConfigured = false;
        });
      }
    } catch (e) {
      print('Error checking AI configuration: $e');
      setState(() {
        _isAiConfigured = false;
      });
    } finally {
      setState(() {
        _isCheckingConfig = false;
      });
    }
  }

  Future<void> _loadAiConfiguration() async {
    try {
      if (_currentUser != null) {
        final docSnapshot = await FirebaseFirestore.instance
            .collection('ai_configurations')
            .doc(_currentUser!.uid)
            .get();

        if (docSnapshot.exists) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          setState(() {
            _aiName = data['name'];
            _aiPersonality = data['personality'];
            _aiInterests = data['interests'];
            _aiCommunicationStyle = data['communicationStyle'];
            _aiLanguage = data['language'];
            _aiProfileImageBase64 = data['profileImage'];
          });
        }
      }
    } catch (e) {
      print('Error loading AI configuration: $e');
    }
  }

  void _onConfigurationComplete() {
    setState(() {
      _isAiConfigured = true;
    });
    _loadAiConfiguration();
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
    try {
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
        if (!subscriptions.containsKey('data') ||
            subscriptions['data'] is! List) {
          return null;
        }

        final activeSubscriptions = (subscriptions['data'] as List).where(
            (sub) =>
                sub is Map &&
                (sub['status'] == 'active' || sub['status'] == 'trialing'));

        if (activeSubscriptions.isNotEmpty) {
          final subscription = activeSubscriptions.first as Map;

          // Vérifier si l'abonnement est en période d'essai
          if (subscription['status'] == 'trialing') {
            _isTrialActive = true;
          }

          // Vérifier si 'plan' existe et contient 'product'
          if (subscription.containsKey('plan') &&
              subscription['plan'] is Map &&
              (subscription['plan'] as Map).containsKey('product')) {
            final productId = subscription['plan']['product'];
            return await _fetchProductName(productId);
          }
        }
      } else {
        print(
            'Error fetching subscription from Stripe: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Exception in _fetchSubscriptionPlan: $e');
    }
    return null;
  }

  Future<String> _fetchProductName(String productId) async {
    try {
      final url = Uri.parse('https://api.stripe.com/v1/products/$productId');
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $stripeSecretKey'},
      );

      if (response.statusCode == 200) {
        final product = jsonDecode(response.body);
        if (product.containsKey('name')) {
          final productName = product['name'].toString();

          if (productName.contains('Standard')) {
            return 'Standard';
          } else if (productName.contains('Pro')) {
            return 'Pro';
          } else if (productName.contains('Business')) {
            return 'Business';
          }
        }
      } else {
        print(
            'Error fetching product name from Stripe: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Exception in _fetchProductName: $e');
    }
    return 'Unknown';
  }

  Future<void> _checkUserSubscription() async {
    try {
      final cid = await _getCustomerId();
      if (cid != null && cid.isNotEmpty) {
        final plan = await _fetchSubscriptionPlan(cid);
        if (mounted) {
          setState(() {
            userSubscriptionPlan = plan;
          });
        }
      }
    } catch (e) {
      print('Error in _checkUserSubscription: $e');
    }
  }

  bool get _isSubscriptionActive {
    return userSubscriptionPlan != null || _isTrialActive;
  }

  // Charger le nombre de requêtes restantes et la limite quotidienne
  Future<void> _loadRemainingQuota() async {
    setState(() {
      _isLoadingQuota = true;
    });

    try {
      // Récupérer l'utilisation quotidienne actuelle et la limite applicable
      if (_currentUser != null) {
        // Si l'utilisateur a un abonnement Pro, on récupère sa limite et son usage
        if (userSubscriptionPlan == 'Pro') {
          final totalLimit = await _quotaManager.getCurrentDailyLimit();
          final remaining = await _quotaManager.getRemainingQuota();

          setState(() {
            _totalDailyLimit =
                totalLimit == -1 ? ApiQuotaManager.proDailyLimit : totalLimit;
            _remainingQuota = remaining == -1 ? _totalDailyLimit : remaining;
          });
        }
        // Si l'utilisateur a un abonnement Standard ou Business, on définit le quota à -1 (illimité)
        else if (_isSubscriptionActive &&
            (userSubscriptionPlan == 'Standard' ||
                userSubscriptionPlan == 'Business')) {
          setState(() {
            _remainingQuota = -1;
          });
        }
        // Pour les utilisateurs gratuits ou autres cas
        else {
          final remaining = await _quotaManager.getRemainingQuota();
          setState(() {
            _totalDailyLimit = ApiQuotaManager.dailyLimit;
            _remainingQuota = remaining;
          });
        }
      } else {
        setState(() {
          _remainingQuota = 0;
        });
      }
    } catch (e) {
      print('Error loading quota: $e');
      setState(() {
        _remainingQuota = 0;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingQuota = false;
        });
      }
    }
  }

  Future<void> _loadMessages() async {
    if (_currentUser == null) return;

    try {
      // Load messages from user-specific collection
      final messagesRef = FirebaseFirestore.instance
          .collection('user_messages')
          .doc(_currentUser!.uid)
          .collection('messages')
          .orderBy('timestamp', descending: false);

      final snapshot = await messagesRef.get();

      if (mounted) {
        setState(() {
          _messages.clear();
          for (var doc in snapshot.docs) {
            final data = doc.data();
            _messages.add(Message(
              content: data['content'] ?? '',
              isUser: data['isUser'] ?? true,
              timestamp: (data['timestamp'] as Timestamp).toDate(),
              imageBase64: data['imageBase64'],
              isGeneratedResponse: data['isGeneratedResponse'] ?? false,
            ));
          }
        });
      }
    } catch (e) {
      print('Error loading messages from Firestore: $e');

      // Fallback to SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final messagesJson = prefs.getStringList('chat_messages') ?? [];

        if (mounted) {
          setState(() {
            _messages.clear();
            _messages.addAll(
              messagesJson
                  .map((message) => Message.fromJson(jsonDecode(message)))
                  .toList(),
            );
          });
        }
      } catch (e) {
        print('Error loading messages from SharedPreferences: $e');
      }
    }
  }

  Future<void> _saveMessages() async {
    if (_currentUser == null) return;

    try {
      // Save latest message to Firestore under user's collection
      final batch = FirebaseFirestore.instance.batch();
      final messagesRef = FirebaseFirestore.instance
          .collection('user_messages')
          .doc(_currentUser!.uid)
          .collection('messages');

      // Clear old messages and add current ones
      final oldMessages = await messagesRef.get();
      for (var doc in oldMessages.docs) {
        batch.delete(doc.reference);
      }

      // Add all current messages with new IDs
      for (var message in _messages) {
        final newDoc = messagesRef.doc();
        batch.set(newDoc, {
          'content': message.content,
          'isUser': message.isUser,
          'timestamp': Timestamp.fromDate(message.timestamp),
          'imageBase64': message.imageBase64,
          'isGeneratedResponse': message.isGeneratedResponse,
        });
      }

      await batch.commit();
    } catch (e) {
      print('Error saving messages to Firestore: $e');

      // Fallback to SharedPreferences
      try {
        final prefs = await SharedPreferences.getInstance();
        final messagesJson =
            _messages.map((message) => jsonEncode(message.toJson())).toList();
        await prefs.setStringList('chat_messages', messagesJson);
      } catch (e) {
        print('Error saving messages to SharedPreferences: $e');
      }
    }
  }

  Future<void> _clearChat() async {
    try {
      if (_currentUser != null) {
        // Clear messages from Firestore
        final messagesRef = FirebaseFirestore.instance
            .collection('user_messages')
            .doc(_currentUser!.uid)
            .collection('messages');

        final batch = FirebaseFirestore.instance.batch();
        final snapshots = await messagesRef.get();
        for (var doc in snapshots.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }

      // Also clear from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('chat_messages');

      setState(() {
        _messages.clear();
        _selectedImageBase64 = null;
        _selectedImageBytes = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat cleared successfully')),
      );
    } catch (e) {
      print('Error clearing chat: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error clearing chat: $e')),
      );
    }
  }

  Future<void> _handleSubmitted(String text) async {
    _textController.clear();

    if (text.trim().isEmpty && _selectedImageBase64 == null) return;

    // Vérifier si l'utilisateur peut faire une requête API
    final canMakeRequest = await _quotaManager.canMakeApiRequest();
    if (!canMakeRequest && _remainingQuota == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'You have reached your daily limit of ${userSubscriptionPlan == 'Pro' ? ApiQuotaManager.proDailyLimit : ApiQuotaManager.dailyLimit} requests. ${userSubscriptionPlan == 'Pro' ? '' : 'Please upgrade to a paid plan for more access.'}'),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final userMessage = Message(
      content: text,
      isUser: true,
      imageBase64: _selectedImageBase64,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMessage);
      _isLoading = true;
      // Clear the selected image immediately after sending
      _selectedImageBytes = null;
      _selectedImageBase64 = null;
    });

    await _saveMessages();
    _scrollToBottom();

    try {
      // Modify prompt based on AI configuration if available
      String contextualPrompt = text;
      if (_isAiConfigured) {
        contextualPrompt = _createContextualizedPrompt(text);
      }

      final response = await _callGroqAPI(contextualPrompt);

      // Enregistrer l'utilisation de l'API
      await _quotaManager.recordApiUsage();

      // Mettre à jour le quota restant
      await _loadRemainingQuota();

      final aiMessage = Message(
        content: response,
        isUser: false,
        timestamp: DateTime.now(),
        isGeneratedResponse: true,
      );

      setState(() {
        _messages.add(aiMessage);
        _isLoading = false;
      });

      await _saveMessages();
      _scrollToBottom();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add(Message(
          content: "Error: $e",
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
      await _saveMessages();
    }
  }

  String _createContextualizedPrompt(String userMessage) {
    String systemPrompt = "You are an AI assistant";

    if (_aiName != null && _aiName!.isNotEmpty) {
      systemPrompt += " named $_aiName";
    }

    if (_aiPersonality != null && _aiPersonality!.isNotEmpty) {
      systemPrompt += " with a personality that is $_aiPersonality";
    }

    if (_aiInterests != null && _aiInterests!.isNotEmpty) {
      systemPrompt +=
          ". You have particular interest and knowledge in $_aiInterests";
    }

    if (_aiCommunicationStyle != null && _aiCommunicationStyle!.isNotEmpty) {
      systemPrompt += ". Your communication style is $_aiCommunicationStyle";
    }

    if (_aiLanguage != null && _aiLanguage != 'English') {
      systemPrompt += ". Please respond in $_aiLanguage language";
    }

    // Enhanced instructions for more natural conversation
    systemPrompt +=
        ". Respond naturally as if you were having a genuine conversation. ";

    // Adapt to message length and conversation stage
    if (userMessage.trim().split(' ').length <= 3) {
      systemPrompt +=
          "Keep responses brief and contextual for short messages. ";
    }

    // Conversation flow improvements
    systemPrompt +=
        "Vary your greetings and avoid repetitive patterns like 'coucou, ça va?' throughout the conversation. ";
    systemPrompt +=
        "After initial greetings, focus on the ongoing conversation without unnecessary reintroductions. ";
    systemPrompt +=
        "Track conversation context and avoid repeating the same conversation starters or pleasantries. ";

    // Personality and response guidance
    systemPrompt +=
        "Never explicitly state your personality traits, interests, or communication style. ";
    systemPrompt +=
        "Do not introduce yourself or your capabilities unless directly asked. ";
    systemPrompt +=
        "Stay on topic and only provide information relevant to the user's message. ";
    systemPrompt +=
        "Your personality should be expressed through your tone, word choice, and conversation flow. ";
    systemPrompt +=
        "Maintain conversation continuity by referencing previous exchanges when appropriate.";

    systemPrompt += " The user is asking: ";

    return systemPrompt + userMessage;
  }

  // Vérification du statut d'abonnement
  Future<void> _checkSubscriptionStatus() async {
    setState(() {
      _isSubscriptionLoading = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      String? cid;

      if (user != null) {
        try {
          DocumentSnapshot userData = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userData.exists) {
            final data = userData.data() as Map<String, dynamic>?;
            if (data != null && data.containsKey('customerId')) {
              cid = data['customerId'] as String?;
            }
          }
        } catch (e) {
          print('Error fetching user data: $e');
          cid = null;
        }
      }

      customerId = cid;

      // Réinitialiser les valeurs par défaut
      _isSubscribed = false;
      _isTrialActive = false;
      userSubscriptionPlan = null;

      if (customerId != null && customerId!.isNotEmpty) {
        await _checkUserSubscription();

        // Vérifier l'état actif de l'abonnement
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

            final hasActiveSubscription = subsList.any((sub) =>
                sub is Map &&
                (sub['status'] == 'active' || sub['status'] == 'trialing'));

            if (mounted) {
              setState(() {
                _isSubscribed = hasActiveSubscription;
              });
            }
          }
        }
      }
    } catch (e) {
      print('Error checking subscription: $e');
      if (mounted) {
        setState(() {
          _isSubscribed = false;
          _isTrialActive = false;
          userSubscriptionPlan = null;
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

  Future<String> _callGroqAPI(String prompt) async {
    try {
      // Using the Groq package instead of direct HTTP call
      return await _groqApiService.generateContent(prompt);
    } catch (e) {
      throw Exception('Groq API error: $e');
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

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  // Handle subscription navigation logic
  Future<void> _handleSubscriptionNavigation() async {
    // If subscription status is still loading, wait for it to complete
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
                  Text("Checking Subscription...")
                ],
              ),
            ),
          );
        },
      );

      // Wait for subscription check to complete with timeout
      try {
        await Future.doWhile(() => Future.delayed(
            const Duration(milliseconds: 100),
            () => _isSubscriptionLoading)).timeout(const Duration(seconds: 10));
      } catch (e) {
        print("Timeout or error waiting for subscription check: $e");
      }

      // Close the loading dialog if it's still open
      if (context.mounted &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // Now navigate based on subscription status
    if (!context.mounted) return;

    // Re-check status directly before navigating
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

  void _openAiSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AIPersonalitySettings(),
      ),
    ).then((_) {
      // Reload AI configuration when returning from settings
      _loadAiConfiguration();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingConfig) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 20),
              Text(
                "Loading your AI assistant...",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              )
            ],
          ),
        ),
      );
    }

    if (!_isAiConfigured) {
      return AIPersonalityConfig(
        onConfigComplete: _onConfigurationComplete,
      );
    }

    // Calculate responsive width for chat container on desktop
    double containerWidth = MediaQuery.of(context).size.width;
    bool isDesktop = containerWidth > 800;
    double chatWidth = isDesktop ? 800 : containerWidth;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Container(
        constraints: const BoxConstraints.expand(),
        color: Colors.white,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: chatWidth),
            child: Column(
              children: [
                // Clean header bar with quota indicator
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          // Use AI profile image if available
                          CircleAvatar(
                            backgroundImage: _aiProfileImageBase64 != null
                                ? MemoryImage(
                                    base64Decode(_aiProfileImageBase64!))
                                : AssetImage("assets/QQ.jpg") as ImageProvider,
                            radius: 18,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _aiName ?? 'AI Chat',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          // Affichage du quota ou du plan d'abonnement
                          if (!_isLoadingQuota)
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Center(
                                child: _buildQuotaChip(),
                              ),
                            ),
                          // Settings icon for AI personality
                          IconButton(
                            icon:
                                const Icon(Icons.settings, color: Colors.black),
                            onPressed: _openAiSettings,
                            tooltip: 'AI Settings',
                          ),
                          IconButton(
                            icon: const Icon(Icons.remove_circle_sharp,
                                color: Colors.black),
                            onPressed: _clearChat,
                            tooltip: 'Clear chat',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Main chat area
                Expanded(
                  child: Stack(
                    children: [
                      _messages.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Use AI profile image if available
                                  _aiProfileImageBase64 != null
                                      ? CircleAvatar(
                                          radius: 40,
                                          backgroundImage: MemoryImage(
                                              base64Decode(
                                                  _aiProfileImageBase64!)),
                                        )
                                      : Image.asset(
                                          'assets/QQ.jpg',
                                          width: 80,
                                          height: 80,
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  const Icon(
                                            Icons.chat_bubble_outline,
                                            size: 80,
                                            color: Colors.grey,
                                          ),
                                        ),
                                  const SizedBox(height: 24),
                                  Text(
                                    "Ask ${_aiName ?? 'me'} any question...",
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  SizedBox(
                                    width: isDesktop ? 500 : 300,
                                    child: Text(
                                      _aiPersonality != null
                                          ? "$_aiPersonality\nAI assistant ready to help"
                                          : "I'm your AI assistant ready to help",
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 16,
                                      ),
                                      textAlign: TextAlign.center,
                                      maxLines: 10,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              itemCount: _messages.length,
                              itemBuilder: (context, index) {
                                final message = _messages[index];
                                return _buildMessageItem(message);
                              },
                            ),

                      // Loading indicator overlay - positioned at bottom of messages
                      if (_isLoading)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 16, horizontal: 16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor: Colors.blue[100],
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: _aiProfileImageBase64 != null
                                        ? Image.memory(
                                            base64Decode(
                                                _aiProfileImageBase64!),
                                            width: 36,
                                            height: 36,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(
                                              Icons.smart_toy_outlined,
                                              size: 24,
                                              color: Colors.black,
                                            ),
                                          )
                                        : Image.asset(
                                            'assets/QQ.jpg',
                                            width: 36,
                                            height: 36,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(
                                              Icons.smart_toy_outlined,
                                              size: 24,
                                              color: Colors.black,
                                            ),
                                          ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(18),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.05),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.blue[400],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        "Thinking...",
                                        style: TextStyle(
                                          color: Colors.grey[700],
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
                    ],
                  ),
                ),

                // Selected image preview
                if (_selectedImageBytes != null)
                  Container(
                    height: 80, // Reduced height
                    width: double.infinity,
                    color: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _selectedImageBytes!,
                            height: 60, // Reduced size
                            width: 60, // Reduced size
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 60, // Reduced size
                                width: 60, // Reduced size
                                color: Colors.grey[300],
                                child: const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _selectedImageBytes = null;
                              _selectedImageBase64 = null;
                            });
                          },
                        ),
                      ],
                    ),
                  ),

                // Quota warning when limit reached
                if (!_isLoadingQuota && _remainingQuota == 0)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      border:
                          Border(top: BorderSide(color: Colors.red.shade300)),
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
                                    ? 'You\'ve reached your daily Pro limit of ${ApiQuotaManager.proDailyLimit} generations. Please try again tomorrow.'
                                    : 'You\'ve reached your daily free limit of ${ApiQuotaManager.dailyLimit} generations. Upgrade to a paid plan for more access.',
                                style: TextStyle(
                                  color: Colors.red[700],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (userSubscriptionPlan != 'Pro')
                          TextButton(
                            onPressed: _handleSubscriptionNavigation,
                            child: Text(
                              'Upgrade',
                              style: TextStyle(
                                color: Colors.red[800],
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                // Input area
                _buildInputArea(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Widget to build the quota chip with appropriate display
  Widget _buildQuotaChip() {
    // Case 1: Standard or Business plan (unlimited)
    if (_isSubscriptionActive &&
        (userSubscriptionPlan == 'Standard' ||
            userSubscriptionPlan == 'Business')) {
      return Chip(
        label: Text(
          userSubscriptionPlan ?? 'Premium',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.green[700],
        padding: EdgeInsets.symmetric(horizontal: 8),
      );
    }

    // Case 2: Pro plan (limited but higher quota)
    if (userSubscriptionPlan == 'Pro') {
      return Chip(
        label: Text(
          'Pro $_remainingQuota/$_totalDailyLimit',
          style: TextStyle(
            color: _remainingQuota < 5 ? Colors.white : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor:
            _remainingQuota < 5 ? Colors.red[700] : Colors.green[700],
        padding: EdgeInsets.symmetric(horizontal: 8),
      );
    }

    // Case 3: Free plan or no plan
    return Chip(
      label: Text(
        '$_remainingQuota/${ApiQuotaManager.dailyLimit}',
        style: TextStyle(
          color: _remainingQuota < 5 ? Colors.white : Colors.black87,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: _remainingQuota < 5
          ? Colors.red[700]
          : (_remainingQuota < 10 ? Colors.orange : Colors.grey[200]),
      padding: EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildMessageItem(Message message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue[100],
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _aiProfileImageBase64 != null
                      ? Image.memory(
                          base64Decode(_aiProfileImageBase64!),
                          width: 32,
                          height: 32,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.smart_toy_outlined,
                            size: 20,
                            color: Colors.black,
                          ),
                        )
                      : Image.asset(
                          'assets/QQ.jpg',
                          width: 32,
                          height: 32,
                          errorBuilder: (context, error, stackTrace) =>
                              const Icon(
                            Icons.smart_toy_outlined,
                            size: 20,
                            color: Colors.black,
                          ),
                        ),
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(14),
              margin: EdgeInsets.only(
                left: message.isUser ? 60.0 : 0.0,
                right: message.isUser ? 0.0 : 0.0,
              ),
              decoration: BoxDecoration(
                color: message.isUser ? const Color(0xFFE3F2FD) : Colors.white,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.imageBase64 != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: 180, // Reduced max height
                            maxWidth: 250, // Added max width
                          ),
                          child: Image.memory(
                            base64Decode(message.imageBase64!),
                            fit: BoxFit.contain, // Changed to contain
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 220, // Reduced height
                                width: 260, // Reduced width
                                color: Colors.grey[200],
                                child: const Center(
                                  child: Text(
                                    "Unable to display image",
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  SelectableText(
                    message.content,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: message.isUser
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    children: [
                      Text(
                        _formatTimestamp(message.timestamp),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                      if (!message.isUser && message.isGeneratedResponse) ...[
                        const SizedBox(width: 12),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: message.content));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Response copied to clipboard'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.copy_outlined,
                              size: 14,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser)
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: _currentUser?.photoURL != null
                  ? CircleAvatar(
                      radius: 16,
                      backgroundImage:
                          CachedNetworkImageProvider(_currentUser!.photoURL!),
                    )
                  : CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.black,
                      child: const Icon(
                        Icons.person,
                        size: 18,
                        color: Colors.white,
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    // Vérifier si l'utilisateur peut envoyer un message
    final bool canSendMessage =
        !_isLoading && (_remainingQuota > 0 || _remainingQuota == -1);

    return Padding(
      padding: EdgeInsets.only(bottom: 1.h),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: canSendMessage,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          hintText:
                              canSendMessage ? 'Ask your question...' : '...',
                          hintStyle: TextStyle(color: Colors.grey[400]),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 6.0),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(50),
                          onTap: canSendMessage
                              ? () => _handleSubmitted(_textController.text)
                              : null,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: canSendMessage
                                  ? Colors.black
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(50),
                              boxShadow: canSendMessage
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.4),
                                        blurRadius: 5,
                                        offset: const Offset(0, 2),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              Icons.send_rounded,
                              color:
                                  canSendMessage ? Colors.white : Colors.black,
                              size: 20,
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
    );
  }
}
