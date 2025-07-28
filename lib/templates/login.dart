//ignore_for_file: depend_on_referenced_packages, deprecated_member_use, unused_local_variable
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_fonts/google_fonts.dart';
import '../services/authentication.dart';
import '../widgets/country.dart';
import 'home.dart';

class ApiRateLimiter {
  static int _requestCount = 0;
  static DateTime? _windowStart;
  static const int _maxRequests = 45;
  static const Duration _windowDuration = Duration(minutes: 1);

  static void _resetWindow() {
    _requestCount = 0;
    _windowStart = DateTime.now();
  }

  static Future<bool> canMakeRequest() async {
    final now = DateTime.now();

    if (_windowStart == null ||
        now.difference(_windowStart!) >= _windowDuration) {
      _resetWindow();
      return true;
    }

    if (_requestCount >= _maxRequests) {
      final timeUntilReset = _windowDuration - now.difference(_windowStart!);
      await Future.delayed(const Duration(seconds: 1));
      return false;
    }

    return true;
  }

  static void incrementRequestCount() {
    _requestCount++;
  }
}

class GeoBlockService {
  static final List<String> blockedCountries = [
    'RU',
    'CN',
    'KP',
    'IR',
    'SY',
    'CU',
    'BY',
    'MM',
    'AF',
    'CY',
    'CZ',
    'BG',
  ];

  static Future<bool> isCountryBlocked() async {
    bool requestSuccessful = false;
    while (!requestSuccessful) {
      if (await ApiRateLimiter.canMakeRequest()) {
        try {
          final response = await http.get(Uri.parse('http://ip-api.com/json'));
          ApiRateLimiter.incrementRequestCount();

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final countryCode = data['countryCode'];
            return blockedCountries.contains(countryCode);
          } else if (response.statusCode == 429) {
            // Rate limit atteint
            await Future.delayed(const Duration(seconds: 1));
            continue;
          }
          requestSuccessful = true;
        } catch (e) {
          debugPrint('Erreur de géolocalisation: $e');
          return false;
        }
      } else {
        // Attendre avant de réessayer
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    return false;
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  bool _isLoading = false;
  late bool _isDarkMode;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    checkGeoBlock();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Modifier la méthode checkGeoBlock() dans _LoginScreenState
  Future<void> checkGeoBlock() async {
    setState(() {
      _isLoading = true;
    });

    bool isBlocked = await GeoBlockService.isCountryBlocked();

    setState(() {
      _isLoading = false;
    });

    if (isBlocked && mounted) {
      if (context.mounted) {
        // Vérification supplémentaire
        showDialog(
          context: context,
          barrierDismissible: false,
          barrierColor: Colors.black.withOpacity(0.5),
          builder: (BuildContext context) => WillPopScope(
            onWillPop: () async {
              // Au lieu de pushReplacement, utiliser pop puis push
              Navigator.of(context).pop(); // Ferme d'abord le dialog
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const Home()),
                (route) => false, // Supprime toute la pile de navigation
              );
              return false; // Empêche le comportement par défaut
            },
            child: Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 10,
              child: Container(
                width: MediaQuery.of(context).size.width > 600
                    ? MediaQuery.of(context).size.width * 0.3
                    : MediaQuery.of(context).size.width * 0.8,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 20),
                    Text(
                      'App unavailable',
                      style: GoogleFonts.poppins(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF2D3142),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Unfortunately, PyperStrategy is only available in certain regions right now. Please contact support if you believe you are receiving this message in error.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: const Color(0xFF4F4F4F),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2D3142),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        minimumSize: const Size(240, 50),
                      ),
                      onPressed: () {
                        Navigator.of(context)
                            .push(
                          MaterialPageRoute(
                            builder: (context) => const Support(),
                          ),
                        )
                            .then((_) {
                          // Gérer le retour de la page Support
                          if (context.mounted) {
                            Navigator.of(context).pop(); // Ferme le dialog
                            Navigator.of(context).pushAndRemoveUntil(
                              MaterialPageRoute(
                                  builder: (context) => const Home()),
                              (route) => false,
                            );
                          }
                        });
                      },
                      child: Text(
                        'View supported countries',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (context) => const Home()),
                          (route) => false,
                        );
                      },
                      child: Text(
                        'Return to Home',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF6E7191),
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Détermine la disposition en fonction de la taille de l'écran
    bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor:
          _isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FD),
      body: Stack(
        children: [
          // Fond décoratif
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: isDesktop ? 400 : 200,
              height: isDesktop ? 400 : 200,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF6C63FF).withOpacity(0.2),
                    Colors.transparent,
                  ],
                  radius: 0.8,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            child: Container(
              width: isDesktop ? 300 : 150,
              height: isDesktop ? 300 : 150,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF4ECDC4).withOpacity(0.2),
                    Colors.transparent,
                  ],
                  radius: 0.8,
                ),
              ),
            ),
          ),

          // Contenu principal
          Center(
            child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
          ),

          // Indicateur de chargement
          if (_isLoading)
            Container(
              color: Colors.black26,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF6C63FF)),
                      ),
                      const SizedBox(height: 15),
                      Text(
                        'Checking location...',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.black87,
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

  Widget _buildDesktopLayout() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(40),
          child: _buildLoginCard(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          _buildLoginCard(),
        ],
      ),
    );
  }

  Widget _buildLoginCard() {
    return Container(
      width: 400,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Logo animé avec effet de pulsation
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Transform.scale(
                scale: 1.0 + 0.03 * _animationController.value,
                child: Container(
                  height: 100,
                  width: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C63FF).withOpacity(0.2),
                        blurRadius: 20,
                        spreadRadius: 5 * _animationController.value,
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: CachedNetworkImage(
                      imageUrl:
                          "https://firebasestorage.googleapis.com/v0/b/youcloud-c5d07.appspot.com/o/photo_2024-09-13_15-06-48-removebg-preview.png?alt=media&token=a1f3ac40-33fc-45f9-a295-43b7a6d5be9e",
                      placeholder: (context, url) => Image.asset(
                        "assets/QQ.jpg",
                        fit: BoxFit.cover,
                      ),
                      errorWidget: (context, url, error) => Image.asset(
                        "assets/QQ.jpg",
                        fit: BoxFit.cover,
                      ),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 30),
          Text(
            'Sign in',
            style: GoogleFonts.poppins(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _isDarkMode ? Colors.white : const Color(0xFF2D3142),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Make a new doc to bring your words, data, and teams together',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 14,
              height: 1.5,
              color: _isDarkMode ? Colors.white70 : const Color(0xFF6E7191),
            ),
          ),
          const SizedBox(height: 40),
          Text(
            'Sign in with',
            style: GoogleFonts.poppins(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _isDarkMode ? Colors.white70 : const Color(0xFF6E7191),
            ),
          ),
          const SizedBox(height: 24),

          // Boutons de connexion sociale améliorés
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildSocialButton(
                icon: "google",
                localImg: Image.asset(
                  "assets/ggg.png",
                  height: 24,
                ),
                imageUrl:
                    'https://firebasestorage.googleapis.com/v0/b/youcloud-c5d07.appspot.com/o/google_icon_130924-removebg-preview.png?alt=media&token=77092126-dd66-40b4-8c0c-b7e88bb28bb5',
                onPressed: () async {
                  setState(() {
                    _isLoading = true;
                  });
                  AuthenticationService auth = AuthenticationService();
                  await auth.signInWithGoogle(context);
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
              ),
              const SizedBox(width: 20),
              _buildSocialButton(
                icon: "github",
                localImg: Image.asset(
                  "assets/ghb.png",
                  height: 24,
                ),
                imageUrl:
                    'https://firebasestorage.googleapis.com/v0/b/youcloud-c5d07.appspot.com/o/github-logo_icon-icons.com_73546.png?alt=media&token=b0ade432-b386-427b-82ae-5e138fedb407',
                onPressed: () async {
                  setState(() {
                    _isLoading = true;
                  });
                  final auth = AuthenticationService();
                  await auth.signInWithGitHub(context);
                  if (mounted) {
                    setState(() {
                      _isLoading = false;
                    });
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 40),

          // Message de sécurité en bas
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.security,
                size: 16,
                color: _isDarkMode ? Colors.white60 : Colors.grey[500],
              ),
              const SizedBox(width: 8),
              Text(
                'Secure login with end-to-end encryption',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: _isDarkMode ? Colors.white60 : Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton({
    required String imageUrl,
    required String icon,
    required VoidCallback onPressed,
    required Widget localImg,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 120,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color:
              _isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFF7F7FC),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isDarkMode ? const Color(0xFF3A3A3A) : Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: CachedNetworkImage(
                  imageUrl: imageUrl,
                  placeholder: (context, url) => localImg,
                  errorWidget: (context, url, error) => localImg,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              icon == "google" ? 'Google' : 'GitHub',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _isDarkMode ? Colors.white : const Color(0xFF2D3142),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
