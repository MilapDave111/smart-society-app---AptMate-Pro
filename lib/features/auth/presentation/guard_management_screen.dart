import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import 'package:flutter/services.dart';

class GuardManagementScreen extends StatefulWidget {
  final String orgId;
  const GuardManagementScreen({super.key, required this.orgId});

  @override
  State<GuardManagementScreen> createState() => _GuardManagementScreenState();
}

class _GuardManagementScreenState extends State<GuardManagementScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showAddForm = false; // Toggles between List View and Form View

  void _addGuard() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;

      if (_phoneController.text.length != 10) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone number must be exactly 10 digits", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
        return;
      }
    }

    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isLoading = true);

    FirebaseApp? tempApp;
    try {
      // 1. Secondary App trick to prevent Admin logout
      tempApp = await Firebase.initializeApp(name: 'tempRegisterGuard', options: Firebase.app().options);

      // 2. Register Guard in Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instanceFor(app: tempApp).createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final String newUid = userCredential.user!.uid;

      // 3. Save Guard data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(newUid).set({
        'uid': newUid,
        'email': _emailController.text.trim(),
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': 'guard',
        'org_id': widget.orgId, // INJECT ORG_ID
        'status': 'Active',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _nameController.clear(); _phoneController.clear(); _emailController.clear(); _passwordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Guard Account Created", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));

        // Return to the list view immediately upon success
        setState(() => _showAddForm = false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Auth Error", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } catch (e) {
      debugPrint("Error adding guard: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (tempApp != null) await tempApp.delete();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _removeGuard(String docId) async {
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();
  }

  // Handles back navigation logic cleanly
  void _handleBackPress() {
    if (_showAddForm) {
      setState(() => _showAddForm = false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_showAddForm) {
          setState(() => _showAddForm = false);
          return false; // Prevent popping the actual screen, just switch view
        }
        return true; // Allow normal screen pop
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppTheme.primary),
            onPressed: _handleBackPress,
          ),
          title: Text(
              _showAddForm ? "Register Guard" : "Security Roster",
              style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 19.6, fontWeight: FontWeight.bold)
          ),
          actions: [
            // Only show the Add button if we are currently looking at the list
            if (!_showAddForm)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _showAddForm = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.5))
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.person_add, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text("Add Guard", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800), // Caps max width to prevent stretching on tablets
            child: _showAddForm ? _buildFormView() : _buildListView(),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Enter Guard Details", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            _buildPremiumInput(controller: _nameController, label: "Guard Full Name", icon: Icons.person),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _phoneController, label: "Phone Number", icon: Icons.phone, isNumber: true),
            const SizedBox(height: 15),
            const Divider(color: AppTheme.borderHalf),
            const SizedBox(height: 15),
            const Text("App Login Credentials", style: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildPremiumInput(controller: _emailController, label: "Email Address", icon: Icons.email),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _passwordController, label: "Temporary Password", icon: Icons.lock, isPassword: true),
            const SizedBox(height: 32),

            InkWell(
              onTap: _isLoading ? null : _addGuard,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(gradient: AppTheme.goldGradient, borderRadius: BorderRadius.circular(12), boxShadow: const [AppTheme.glowEffect]),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("Create Account", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Text("Active Personnel", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users')
                .where('role', isEqualTo: 'guard')
                .where('org_id', isEqualTo: widget.orgId) // SCOPED QUERY
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No active guards found.", style: TextStyle(color: AppTheme.textMuted)));

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: AppTheme.background, shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withOpacity(0.5))),
                        child: const Icon(Icons.security, color: AppTheme.primary),
                      ),
                      title: Text(data['name'] ?? 'Unknown', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                      subtitle: Text(data['email'] ?? data['phone'] ?? 'No Data', style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.error), onPressed: () => _removeGuard(docs[index].id)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false, bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.phone : TextInputType.text,
      // THE FIX: Strictly enforce 10 digits and block non-numeric characters
      inputFormatters: isNumber
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]
          : null,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted),
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
        filled: true,
        fillColor: AppTheme.background,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }
}