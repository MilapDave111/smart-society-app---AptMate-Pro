import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import 'dashboard_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _societyController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isLogin = true; // Toggles between Login and Admin Registration

  void _submitForm() async {
    final emailStr = _emailController.text.trim();
    final passwordStr = _passwordController.text.trim();
    final nameStr = _nameController.text.trim();
    final societyStr = _societyController.text.trim();

    if (emailStr.isEmpty || !emailStr.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid email address", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }
    if (passwordStr.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }
    if (!_isLogin && (nameStr.isEmpty || societyStr.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Name and Society Name are required for registration.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isLogin) {
        // LOGIN PROTOCOL
        await FirebaseAuth.instance.signInWithEmailAndPassword(email: emailStr, password: passwordStr);
        _navigateToDashboard();
      } else {
        // ADMIN SINGLE-STEP REGISTRATION PROTOCOL
        final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailStr, password: passwordStr);
        final user = userCred.user;

        if (user != null) {
          String? fcmToken;
          try { fcmToken = await FirebaseMessaging.instance.getToken(); } catch (_) {}

          // Generate a unique org_id for the new society
          final String newOrgId = FirebaseFirestore.instance.collection('organizations').doc().id;

          // Register the organization
          await FirebaseFirestore.instance.collection('organizations').doc(newOrgId).set({
            'org_id': newOrgId,
            'societyName': societyStr,
            'adminUid': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
          });

          // Register the SUPER_ADMIN with the linked org_id
          await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
            'uid': user.uid,
            'email': user.email,
            'fcmToken': fcmToken ?? '',
            'name': nameStr,
            'role': 'SUPER_ADMIN',
            'societyName': societyStr,
            'org_id': newOrgId,
            'wing': 'N/A',
            'flatNumber': 'N/A',
            'status': 'Inside',
            'createdAt': FieldValue.serverTimestamp(),
          });
          _navigateToDashboard();
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      String errorMsg = "Authentication Failed";
      if (e.code == 'user-not-found' || e.code == 'invalid-email') errorMsg = "No account found for this email.";
      else if (e.code == 'wrong-password' || e.code == 'invalid-credential') errorMsg = "Incorrect password.";
      else if (e.code == 'email-already-in-use') errorMsg = "This email is already registered.";
      else errorMsg = e.message ?? "An error occurred.";

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg, style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("System Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    }
  }

  void _navigateToDashboard() {
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const DashboardScreen()));
    }
  }

  void _showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(text: _emailController.text);
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.borderHalf)),
            title: const Row(
              children: [
                Icon(Icons.lock_reset, color: AppTheme.primary), SizedBox(width: 10),
                Text("Reset Password", style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                    "Enter your registered email address. A secure password reset link will be sent to you.\n\nIMPORTANT: If you do not see the email within 2 minutes, check your Spam or Junk folder.",
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 13)
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: resetEmailController, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: "Email Address", labelStyle: const TextStyle(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.email, color: AppTheme.textMuted, size: 20),
                    filled: true, fillColor: AppTheme.background,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: isSending ? null : () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: isSending ? null : () async {
                  final email = resetEmailController.text.trim();
                  if (email.isEmpty || !email.contains('@')) return;
                  setDialogState(() => isSending = true);
                  try {
                    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Reset link sent. Check your Inbox and Spam folder.", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
                        backgroundColor: AppTheme.success, duration: Duration(seconds: 5),
                      ));
                    }
                  } catch (e) {
                    setDialogState(() => isSending = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
                  }
                },
                child: isSending ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2)) : const Text("Send Link", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              )
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isLandscapeTablet = screenWidth > 800;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: isLandscapeTablet
                ? ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 1, child: _buildBranding()), const SizedBox(width: 48),
                  Flexible(flex: 1, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 450), child: _buildFormCard())),
                ],
              ),
            )
                : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 450),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [_buildBranding(), const SizedBox(height: 48), _buildFormCard()],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBranding() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(gradient: AppTheme.goldGradient, shape: BoxShape.circle, boxShadow: const [AppTheme.glowEffect]),
          child: Image.asset('assets/images/logo.png', width: 85, height: 85),
        ),
        const SizedBox(height: 24),
        Text("Smart Society", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 36, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text("PREMIUM SYSTEM", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, letterSpacing: 2.0, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderHalf), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, 10))],
      ),
      child: _buildAuthForms(),
    );
  }

  Widget _buildAuthForms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_isLogin ? "Secure Access" : "Admin Registration", style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(_isLogin ? "Enter your credentials to access the system." : "Create an administrator account to initialize a society.", style: const TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 24),

        if (!_isLogin) ...[
          TextField(
            controller: _nameController, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              labelText: "Full Name", labelStyle: const TextStyle(color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.person_outline, color: AppTheme.textMuted),
              filled: true, fillColor: AppTheme.background,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _societyController, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              labelText: "Society Name", labelStyle: const TextStyle(color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.business, color: AppTheme.textMuted),
              filled: true, fillColor: AppTheme.background,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 20),
        ],

        TextField(
          controller: _emailController, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: "Email Address", labelStyle: const TextStyle(color: AppTheme.textMuted),
            prefixIcon: const Icon(Icons.email_outlined, color: AppTheme.textMuted),
            filled: true, fillColor: AppTheme.background,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 20),

        TextField(
          controller: _passwordController, obscureText: _obscurePassword, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
          decoration: InputDecoration(
            labelText: "Password", labelStyle: const TextStyle(color: AppTheme.textMuted),
            prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted),
            suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
            filled: true, fillColor: AppTheme.background,
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
          ),
        ),

        if (_isLogin)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: _isLoading ? null : _showForgotPasswordDialog, child: const Text("Forgot Password?", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))),
          )
        else
          const SizedBox(height: 24),

        InkWell(
          onTap: _isLoading ? null : _submitForm,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(gradient: AppTheme.goldGradient, borderRadius: BorderRadius.circular(12), boxShadow: const [AppTheme.glowEffect]),
            child: Center(
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                  : Text(_isLogin ? "Authenticate" : "Register Admin", style: const TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: TextButton(
            onPressed: _isLoading ? null : () => setState(() { _isLogin = !_isLogin; _passwordController.clear(); }),
            child: Text(_isLogin ? "New Society? Register Admin" : "Already an Admin/Resident? Login", style: const TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }
}