import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  // THE PASS-THROUGH VARIABLE
  final Widget destination;

  const SplashScreen({super.key, required this.destination});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _routeUser();
  }

  void _routeUser() async {
    // FORCES THE SPLASH SCREEN TO STAY VISIBLE FOR 2.5 SECONDS
    await Future.delayed(const Duration(milliseconds: 3000));

    if (!mounted) return;

    // ROUTES TO WHATEVER MAIN.DART TOLD IT TO
    Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => widget.destination)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(
        children: [
          // --- 1. YOUR MAIN CENTERED CONTENT ---
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(2.5),
                  decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    shape: BoxShape.circle,
                    boxShadow: const [AppTheme.glowEffect],
                  ),
                  child: Image.asset('assets/images/logo.png', width: 100, height: 100),
                ),
                const SizedBox(height: 25),
                Text(
                  "Smart Society",
                  style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 36, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  "AI BASED SECURE APARTMENT MANAGEMENT",
                  style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 12, letterSpacing: 2.0),
                ),
                const SizedBox(height: 40),
                const CircularProgressIndicator(color: AppTheme.primary),
              ],
            ),
          ),

          // --- 2. YOUR UNIVERSITY LOGO FOOTER ---
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 50.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Powered by',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.withOpacity(0.7),
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Image.asset(
                    'assets/images/mu-logo.png', // Ensure this is a transparent PNG
                    height: 40,
                    fit: BoxFit.contain,
                    // FORCES THE TRANSPARENT PNG TO BE GOLD
                    color: AppTheme.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}