import 'package:aptmatepro/features/auth/presentation/family_detail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';
import 'package:flutter/services.dart';

class FamilyManagementScreen extends StatefulWidget {
  final String orgId;
  const FamilyManagementScreen({super.key, required this.orgId});

  @override
  State<FamilyManagementScreen> createState() => _FamilyManagementScreenState();
}

class _FamilyManagementScreenState extends State<FamilyManagementScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _wingController = TextEditingController();
  final _flatController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _showAddForm = false; // Toggles between Directory List and Registration Form

  void _addFamily() async {
    if (_nameController.text.isEmpty || _wingController.text.isEmpty || _flatController.text.isEmpty || _emailController.text.isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }
    if (_phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone number must be exactly 10 digits", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    if (_passwordController.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password must be at least 6 characters", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isLoading = true);

    FirebaseApp? tempApp;
    try {
      // 1. Initialize secondary Firebase app to prevent Admin from being logged out
      tempApp = await Firebase.initializeApp(name: 'tempRegister', options: Firebase.app().options);

      // 2. Create the user in Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instanceFor(app: tempApp).createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final String newUid = userCredential.user!.uid;

      // 3. Save resident details to Firestore linked to the new Auth UID
      await FirebaseFirestore.instance.collection('users').doc(newUid).set({
        'uid': newUid,
        'email': _emailController.text.trim(),
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'wing': _wingController.text.trim().toUpperCase(),
        'flatNumber': _flatController.text.trim(),
        'role': 'resident',
        'org_id': widget.orgId, // INJECT ORG_ID
        'status': 'Left',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _nameController.clear(); _phoneController.clear(); _wingController.clear();
        _flatController.clear(); _emailController.clear(); _passwordController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Family Account Created & Registered", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));

        // Return to the list view immediately upon success
        setState(() => _showAddForm = false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? "Auth Error", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } catch (e) {
      debugPrint("Error adding family: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      // 4. Destroy the secondary app to clean up memory
      if (tempApp != null) await tempApp.delete();
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _removeFamily(String docId) async {
    // Note: This removes Firestore data. Deleting the actual Auth user requires Admin SDK (Cloud Functions).
    await FirebaseFirestore.instance.collection('users').doc(docId).delete();
  }

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
          return false; // Prevent popping the actual screen, switch view instead
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
              _showAddForm ? "Register Family" : "Resident Directory",
              style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)
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
                        Icon(Icons.group_add, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text("Add Family", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800), // Caps max width for tablets/desktop
            child: _showAddForm ? _buildFormView() : _buildListView(),
          ),
        ),
      ),
    );
  }

  // --- REGISTRATION FORM VIEW ---
  Widget _buildFormView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            gradient: AppTheme.cardGradient,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderHalf)
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Register New Family", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            Row(
              children: [
                Expanded(flex: 1, child: _buildPremiumInput(controller: _wingController, label: "Wing (e.g. A)", icon: Icons.domain)),
                const SizedBox(width: 15),
                Expanded(flex: 2, child: _buildPremiumInput(controller: _flatController, label: "Flat No (e.g. 101)", icon: Icons.meeting_room, isNumber: true)),
              ],
            ),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _nameController, label: "Primary Member Name", icon: Icons.person),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _phoneController, label: "Contact Number", icon: Icons.phone, isPhone: true),            const SizedBox(height: 15),
            const Divider(color: AppTheme.borderHalf),
            const SizedBox(height: 15),
            const Text("App Login Credentials", style: TextStyle(color: AppTheme.textMuted, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            _buildPremiumInput(controller: _emailController, label: "Email Address", icon: Icons.email),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _passwordController, label: "Temporary Password", icon: Icons.lock, isPassword: true),
            const SizedBox(height: 32),

            InkWell(
              onTap: _isLoading ? null : _addFamily,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                    gradient: AppTheme.goldGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [AppTheme.glowEffect]
                ),
                child: Center(
                  child: _isLoading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("Create Account & Register", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- DIRECTORY LIST VIEW ---
  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Text("Registered Families", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users')
                .where('role', isEqualTo: 'resident')
                .where('org_id', isEqualTo: widget.orgId) // SCOPED QUERY
                .orderBy('wing').orderBy('flatNumber')
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Database Error:\n${snapshot.error}", style: const TextStyle(color: AppTheme.error), textAlign: TextAlign.center)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No families registered yet.", style: TextStyle(color: AppTheme.textMuted)));

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final String flatDisplay = "${data['wing']}-${data['flatNumber']}";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        // Pass orgId to detail screen
                        Navigator.push(context, MaterialPageRoute(builder: (c) => FamilyDetailScreen(flatId: flatDisplay, primaryName: data['name'] ?? 'Unknown', orgId: widget.orgId)));
                      },
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
                          child: Text(flatDisplay, style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                        title: Text(data['name'] ?? 'Unknown', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: const Text("Tap to view/manage members", style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline, color: AppTheme.error), onPressed: () => _removeFamily(docs[index].id)),
                      ),
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

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false, bool isPassword = false,bool isPhone = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      // Use phone keyboard if isPhone, numeric if isNumber, else default text
      keyboardType: isPhone ? TextInputType.phone : (isNumber ? TextInputType.number : TextInputType.text),
      // THE FIX: Restrict phone to 10 digits, restrict normal numbers to digits only
      inputFormatters: isPhone
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]
          : (isNumber ? [FilteringTextInputFormatter.digitsOnly] : null),
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