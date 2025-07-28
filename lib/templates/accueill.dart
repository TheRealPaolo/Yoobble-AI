// ignore_for_file: use_build_context_synchronously, avoid_print, deprecated_member_use
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dot_json_env/flutter_dot_json_env.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';
import 'package:yoobble/pages/classes/ads.dart';
import 'package:yoobble/pages/classes/email.dart';
import 'package:yoobble/pages/classes/one-shot.dart';
import 'package:yoobble/pages/classes/press.dart';
import '../pages/ai_agent.dart';
import '../pages/chat.dart';
import '../pages/citation.dart';
import '../pages/classes/product.dart';
import '../pages/classes/sale.dart';
import '../pages/classes/script.dart';
import '../pages/classes/social.dart';
import '../pages/translate.dart';
import '../services/authentication.dart';
import '../stripe/paywall.dart';
import 'package:http/http.dart' as http;
import '../stripe/stripeinfo.dart';
import '../utils/contact.dart';
import '../utils/responsive.dart';

class Accueil extends StatefulWidget {
  const Accueil({super.key});

  @override
  State<Accueil> createState() => _AccueilState();
}

class _AccueilState extends State<Accueil> with SingleTickerProviderStateMixin {
  // --- State Variables ---
  int _selectedIndex = 0; // Index for main navigation items
  late AnimationController _controller; // Kept for potential future animations
  // bool _isSidebarOpen = true; // Removed for fixed width sidebar based on image
  bool _isSubscribed = false;
  bool _isSubscriptionLoading = true;
  String? customerId;
  final String stripeSecretKey = dotjsonenv.env['SECRET'] ?? "";
  final bool _isSidebarOpen = true;

  // --- Main Navigation Data (Matching the Image) ---
  final List<Map<String, dynamic>> _mainNavItems = [
    {'label': 'Email', 'icon': FontAwesomeIcons.envelope, 'isNew': false},
    {
      'label': 'Social Media Post',
      'icon': FontAwesomeIcons.hashtag,
      'isNew': false
    },
    {
      'label': 'One-Shot Blog Post',
      'icon': FontAwesomeIcons.bolt,
      'isNew': false
    },
    {
      'label': 'Ads Generator',
      'icon': FontAwesomeIcons.bullhorn,
      'isNew': false
    },
    {
      'label': 'Press Article',
      'icon': FontAwesomeIcons.fileAlt,
      'isNew': false
    },
    {'label': 'Movie Scenario', 'icon': FontAwesomeIcons.film, 'isNew': false},
    {
      'label': 'Sales Copy',
      'icon': FontAwesomeIcons.shoppingCart,
      'isNew': false
    },
    {
      'label': 'Product Description',
      'icon': FontAwesomeIcons.tag,
      'isNew': false
    },
/////////////////////CONTENT////////////////////////////////////////////////////
    {
      'label': 'Yoobble Chat IA',
      'icon': Icons.bubble_chart,
      'isNew': true
    }, // Example icon
    {'label': 'Citation', 'icon': Icons.format_quote, 'isNew': false},
    {'label': 'Translate', 'icon': Icons.translate, 'isNew': false},
    {'label': 'Free AI Agent', 'icon': Icons.rocket, 'isNew': false},
  ];

  // --- Placeholder Pages ---
  // Replace these with your actual page widgets corresponding to the nav items
  final List<Widget> _pages = [
    Center(child: EmailGenerator()),
    Center(child: SocialMediaGenerator()),
    Center(child: BlogPostGenerator()),
    Center(child: AdsGenerator()),
    Center(child: PressArticleGenerator()),
    Center(child: ScriptGenerator()),
    Center(child: SalesCopyGenerator()),
    Center(child: ProductDescriptionGenerator()),
///////CONTENT CREATION //////////////////////
    Center(child: ChatScreen()),
    Center(child: CitationGeneratorPage()),
    Center(child: Translate()),
    Center(child: AiAgent()),
    // Add more pages if needed for items within Channels/DMs if they navigate
  ];

  // --- Methods ---
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    // _controller.forward(); // Not strictly needed if no animations are driven by it initially
    _checkSubscriptionStatus();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Keep your existing subscription check logic
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
              setState(() {
                _isSubscribed = true;
              });
            } else {
              setState(() {
                _isSubscribed = false;
              });
            }
          } else {
            // Handle case where 'data' is not as expected
            print('Stripe response format unexpected: ${response.body}');
            setState(() {
              _isSubscribed = false;
            });
          }
        } else {
          // Handle non-200 responses (e.g., 404 if customer has no subscriptions)
          print('Stripe API error: ${response.statusCode} ${response.body}');
          setState(() {
            _isSubscribed = false;
          });
        }
      } else {
        // No customer ID, so not subscribed
        setState(() {
          _isSubscribed = false;
        });
      }
    } catch (e) {
      print('Error checking subscription: $e');
      setState(() {
        _isSubscribed = false;
      });
    } finally {
      // Use mounted check before calling setState in async finally block
      if (mounted) {
        setState(() {
          _isSubscriptionLoading = false;
        });
      }
    }
  }

  // Keep your existing subscription navigation logic
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

      // Wait for subscription check to complete
      // Use a timeout to prevent infinite waiting
      try {
        await Future.doWhile(() => Future.delayed(
                const Duration(milliseconds: 100),
                () => _isSubscriptionLoading))
            .timeout(const Duration(seconds: 10)); // Example 10 second timeout
      } catch (e) {
        print("Timeout or error waiting for subscription check: $e");
        // Optionally show an error message to the user
      }

      // Close the loading dialog if it's still open
      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }

    // Now navigate based on subscription status
    if (!context.mounted) return;

    // Re-check status directly before navigating as it might have resolved during wait
    if (_isSubscribed) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const SubscriptionInfoPage(), // Your actual page
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              const SubscriptionBottomSheet(), // Your actual page/modal
        ),
      );
    }
  }

  // --- Build Methods ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Main background

      body: ResponsiveWidget(
        mobile: _buildMobileLayout(), // Keep or adapt your mobile layout
        desktop: _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      children: [
        _buildVerticalNavigation(), // The updated sidebar
        Expanded(
          child: Column(
            children: [
              // Optional: Add an AppBar here if needed for the main content area
              // AppBar(title: Text("Content Area"), elevation: 1),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  // Ensure _pages has an element for the current _selectedIndex
                  child: _selectedIndex < _pages.length
                      ? _pages[_selectedIndex]
                      : const Center(child: Text("Select an item")), // Fallback
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

//Mobile Zone
  Widget _buildMobileLayout() {
    // Implement or keep your existing mobile layout
    // It might involve a Drawer instead of a fixed sidebar
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset(
              "assets/QQ.jpg",
              height: 3.h,
            ),
            Text(
              'OOBBLE', // BRAND NAME
              style: GoogleFonts.lusitana(
                // Consider font change
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16, // Slightly larger
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.white,
        elevation: 0,
        leadingWidth: 40,
      ),
      drawer: _buildVerticalNavigation(), // Use sidebar as drawer on mobile?
      body: _selectedIndex < _pages.length
          ? _pages[_selectedIndex]
          : const Center(child: Text("Select an item")),
    );
  }

  // --- THE UPDATED SIDEBAR WIDGET ---
  Widget _buildVerticalNavigation() {
    final currentUser = FirebaseAuth.instance.currentUser;
    final Color sidebarBackgroundColor = Colors.white; // Light background
    final Color borderColor = Colors.white;
    final Color textColor = Colors.grey[800]!;
    final Color iconColor = Colors.grey[600]!;
    final Color selectedColor = Colors.black; // As per image highlight

    return Container(
      width: 200, // Reduced width to avoid overflow
      decoration: BoxDecoration(
          color: sidebarBackgroundColor,
          border: Border(right: BorderSide(color: borderColor, width: 1))),
      child: Column(
        children: [
          // 1. Header (Logo)
          _buildNavHeader(sidebarBackgroundColor),
          const Divider(
              height: 1, color: Colors.transparent), // Add space like in image

          // 2. User Info Section
          _buildUserInfo(currentUser, textColor, iconColor),
          const Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
          ),

          const SizedBox(height: 6), // Reduced spacing further
          // 4. Main Navigation Items - First section (before Content)
          _buildNavItem(0, selectedColor, iconColor, textColor), // Email
          _buildNavItem(
              1, selectedColor, iconColor, textColor), // Social Media Post
          _buildNavItem(
              2, selectedColor, iconColor, textColor), // One-Shot Blog Post
          _buildNavItem(
              3, selectedColor, iconColor, textColor), // Ads Generator
          _buildNavItem(
              4, selectedColor, iconColor, textColor), // Press Article
          _buildNavItem(
              5, selectedColor, iconColor, textColor), // Movie Scenario
          _buildNavItem(6, selectedColor, iconColor, textColor), // Sales Copy
          _buildNavItem(
              7, selectedColor, iconColor, textColor), // Product Description

          const SizedBox(height: 6), // Reduced spacing further

          // Add simple divider for CONTENT section before Yoobble
          const Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 16,
          ),

          const SizedBox(height: 6), // Reduced spacing further

          // Content section items
          _buildNavItem(8, selectedColor, iconColor, textColor), // Chat IA
          _buildNavItem(9, selectedColor, iconColor, textColor), // Citation
          _buildNavItem(10, selectedColor, iconColor, textColor), // Translate
          _buildNavItem(
              11, selectedColor, iconColor, textColor), // Free content

          const SizedBox(height: 6), // Reduced spacing further

          // 5. Expandable Sections Wrapper (for scrolling if needed)
          Expanded(
              child: SingleChildScrollView(
                  // Allows scrolling if content exceeds height
                  )),

          // 6. Footer Section (Usage Info & Upgrade Button)
          const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16), // Reduced divider
          _buildUsageInfo(textColor, selectedColor),
        ],
      ),
    );
  }

  Widget _buildNavHeader(Color bgColor) {
    // Similar to original but styled for light theme
    return Container(
      padding: const EdgeInsets.only(
          top: 10.0,
          bottom: 6.0,
          left: 14,
          right: 14), // Further reduced padding
      // color: bgColor, // Use parent container's color
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween, // Space between logo and bell
        children: [
          // Logo
          Row(
            // Keep logo and potential text together
            children: [
              Image.asset(
                "assets/QQ.jpg",
                height: 3.5.h, // Further reduced
              ),
              SizedBox(width: 2),
              const Text(
                'OOBBLE',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18, // Further reduced
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUserInfo(User? user, Color textColor, Color iconColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 6.0, vertical: 3.0), // Further reduced padding
      child: ListTile(
        dense: true, // Makes it more compact
        leading: CircleAvatar(
          radius: 12, // Further reduced size
          backgroundColor: Colors.grey[300], // Placeholder bg
          backgroundImage: (user?.photoURL != null)
              ? CachedNetworkImageProvider(user!.photoURL!)
              : null, // Use CachedNetworkImageProvider
          child: (user?.photoURL == null)
              ? Icon(Icons.person,
                  size: 14, color: Colors.grey[600]) // Further reduced icon
              : null,
        ),
        title: Text(
          user?.displayName ?? "User Name",
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textColor), // Further reduced font size
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          user?.email ?? "user@example.com",
          style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600]), // Further reduced font size
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, Color selectedColor, Color iconColor, Color textColor) {
    bool isSelected = _selectedIndex == index;
    final item = _mainNavItems[index];

    return isSelected
        ? Padding(
            padding: EdgeInsets.only(right: 0.3.w), // Further reduced padding
            child: Card(
              elevation: 6, // Further reduced elevation
              color: Colors.white.withOpacity(0.5),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4), // Smaller radius
                  onTap: () {
                    setState(() => _selectedIndex = index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 6, horizontal: 8), // Further reduced padding
                    child: Row(
                      children: [
                        Icon(
                          item['icon'] as IconData,
                          size: 18, // Further reduced size
                          color: isSelected ? selectedColor : iconColor,
                        ),
                        const SizedBox(width: 8), // Further reduced spacing
                        Expanded(
                          child: Text(
                            item['label'] as String,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13, // Further reduced size
                              fontFamily: 'Courier',
                              fontWeight: isSelected
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                              color: isSelected ? selectedColor : textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
        : Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4), // Smaller radius
              onTap: () {
                setState(() => _selectedIndex = index);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: 6, horizontal: 8), // Further reduced padding
                child: Row(
                  children: [
                    Icon(
                      item['icon'] as IconData,
                      size: 18, // Further reduced size
                      color: isSelected ? selectedColor : iconColor,
                    ),
                    const SizedBox(width: 8), // Further reduced spacing
                    Expanded(
                      child: Text(
                        item['label'] as String,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13, // Further reduced size
                          fontFamily: 'Courier',
                          fontWeight:
                              isSelected ? FontWeight.w500 : FontWeight.normal,
                          color: isSelected ? selectedColor : textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
  }

  Widget _buildUsageInfo(Color textColor, Color ctaColor) {
    return Padding(
        padding: const EdgeInsets.all(10.0), // Further reduced padding
        child: _buildNavFooter());
  }

  Widget _buildNavFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_isSidebarOpen) ...[
          _buildFooterTile(
            icon: Icons.payment,
            title: _isSubscriptionLoading
                ? "Checking ..."
                : (_isSubscribed ? "Subscription" : "Subscribe"),
            onTap: _handleSubscriptionNavigation,
          ),
          // ContactPage
          _buildFooterTile(
            icon: Icons.quick_contacts_mail_outlined,
            title: "Contact",
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ContactPage()),
            ),
          ),
        ] else ...[
          _buildFooterIconButton(
            icon: Icons.payment,
            onTap: _handleSubscriptionNavigation,
          ),
          _buildFooterIconButton(
            icon: Icons.quick_contacts_mail_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ContactPage()),
            ),
          ),
        ],
        _buildFooterTile(
          icon: Icons.logout,
          title: _isSidebarOpen ? "Log out" : "",
          onTap: () {
            AuthenticationService auth = AuthenticationService();
            auth.signOut(context);
          },
        ),
      ],
    );
  }

  Widget _buildFooterTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: 10, vertical: 0), // Further reduced padding
      leading:
          Icon(icon, color: Colors.black, size: 16), // Further reduced size
      title: title.isNotEmpty
          ? Text(
              title,
              style: const TextStyle(
                fontFamily: 'Courier',
                color: Colors.black,
                fontSize: 11, // Further reduced size
              ),
            )
          : null,
      onTap: onTap,
    );
  }

  Widget _buildFooterIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return IconButton(
      padding: const EdgeInsets.all(8), // Further reduced padding
      constraints: const BoxConstraints(),
      icon: Icon(icon, color: Colors.white, size: 20), // Further reduced size
      onPressed: onTap,
    );
  }
}
