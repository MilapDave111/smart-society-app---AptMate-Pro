import 'package:aptmatepro/features/auth/presentation/admin_complaint_list_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';

import '../../../theme/app_theme.dart';
import 'login_screen.dart';
import 'guard_entry_screen.dart';
import 'maintenance_screen.dart';
import 'notice_board_screen.dart';
import 'visitor_list_screen.dart';
import 'visitor_log_screen.dart';
import 'complaint_list_screen.dart';
import 'family_management_screen.dart';
import 'guard_management_screen.dart';
import 'admin_billing_screen.dart';
import 'guard_resident_scanner_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? _lastNoticeId;
  String? _lastVisitorId;
  bool _newNoticeHighlight = false;
  String? _activePopupVisitorId;

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
  }

  Future<void> _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      String? token = await messaging.getToken();
      final user = FirebaseAuth.instance.currentUser;

      await FirebaseMessaging.instance.subscribeToTopic('all_notices');
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseMessaging.instance.subscribeToTopic('all_complaints');
      }

      if (user != null && token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcmToken': token});
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        if (user != null) FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcmToken': newToken});
      });
    }
  }

  // ==========================================
  // UNIFIED SETTINGS MENU
  // ==========================================
  void _showSettingsMenu(BuildContext context, Map<String, dynamic> userData) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        final user = FirebaseAuth.instance.currentUser;
        final name = userData['name'] ?? "Unknown User";
        final role = (userData['role'] ?? "Resident").toString().toUpperCase();
        final email = user?.email ?? "No Email";

        return Dialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.borderHalf)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("System Settings", style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                  const Divider(color: AppTheme.border, height: 30),

                  // 1. User Profile Details
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppTheme.background, shape: BoxShape.circle, border: Border.all(color: AppTheme.primary)),
                        child: Text(name.isNotEmpty ? name.substring(0, 1).toUpperCase() : "U", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 20)),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(email, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            Text("Role: $role", style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Options
                  _buildSettingItem(Icons.lock, "Change Password", () {
                    Navigator.pop(dialogContext);
                    _showChangePasswordDialog(context);
                  }),
                  _buildSettingItem(Icons.info_outline, "About Developer", () {
                    Navigator.pop(dialogContext);
                    _showAboutDeveloperDialog(context);
                  }),
                  _buildSettingItem(Icons.logout, "Secure Logout", () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (Route<dynamic> route) => false);
                  }, isDestructive: false),
                  const Divider(color: AppTheme.border, height: 30),

                  _buildSettingItem(Icons.delete_forever, "Delete Account Data", () {
                    Navigator.pop(dialogContext);
                    if (user != null) _showDeleteAccountDialog(context, user);
                  }, isDestructive: true),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingItem(IconData icon, String title, VoidCallback onTap, {bool isDestructive = false}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: isDestructive ? AppTheme.error : AppTheme.textMuted),
      title: Text(title, style: TextStyle(color: isDestructive ? AppTheme.error : AppTheme.textPrimary, fontSize: 14, fontWeight: isDestructive ? FontWeight.bold : FontWeight.normal)),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.border, size: 20),
      onTap: onTap,
    );
  }

  // ==========================================
  // RESTORED: EXACT ORIGINAL CHANGE PASSWORD
  // ==========================================
  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    bool isProcessing = false;
    bool obscureCurrent = true;
    bool obscureNew = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.borderHalf)),
            title: const Row(
              children: [
                Icon(Icons.password, color: AppTheme.primary),
                SizedBox(width: 10),
                Text("Change Password", style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("For security, you must verify your current password to set a new one.", style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                const SizedBox(height: 15),
                TextField(
                  controller: currentPasswordController, obscureText: obscureCurrent,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: "Current Password", labelStyle: const TextStyle(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.lock_outline, color: AppTheme.textMuted, size: 20),
                    suffixIcon: IconButton(icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted), onPressed: () => setDialogState(() => obscureCurrent = !obscureCurrent)),
                    filled: true, fillColor: AppTheme.background,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: newPasswordController, obscureText: obscureNew,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: "New Password (Min 6 chars)", labelStyle: const TextStyle(color: AppTheme.textMuted),
                    prefixIcon: const Icon(Icons.key, color: AppTheme.textMuted, size: 20),
                    suffixIcon: IconButton(icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility, color: AppTheme.textMuted), onPressed: () => setDialogState(() => obscureNew = !obscureNew)),
                    filled: true, fillColor: AppTheme.background,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(context),
                child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
                onPressed: isProcessing ? null : () async {
                  if (newPasswordController.text.length < 6) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New password must be at least 6 characters.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
                    return;
                  }

                  setDialogState(() => isProcessing = true);
                  try {
                    User user = FirebaseAuth.instance.currentUser!;
                    AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: currentPasswordController.text);
                    await user.reauthenticateWithCredential(credential);
                    await user.updatePassword(newPasswordController.text);

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password updated successfully. Please use your new password next time.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
                    }
                  } catch (e) {
                    setDialogState(() => isProcessing = false);
                    String errorMsg = "Update failed. Check current password.";
                    if (e is FirebaseAuthException && e.code == 'wrong-password') errorMsg = "Incorrect current password.";
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errorMsg, style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
                  }
                },
                child: isProcessing
                    ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                    : const Text("Update Password", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              )
            ],
          );
        },
      ),
    );
  }

  // ==========================================
  // RESTORED: EXACT ORIGINAL ABOUT DEVELOPER
  // ==========================================
  void _showAboutDeveloperDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28), side: const BorderSide(color: AppTheme.borderHalf)),
          backgroundColor: AppTheme.cardBg,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 450),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/mu-logo.png',
                      height: 50, fit: BoxFit.contain, color: AppTheme.primary,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.school_rounded, size: 50, color: AppTheme.primary),
                    ),
                    const SizedBox(height: 24),
                    Text('Milap Dave', textAlign: TextAlign.center, style: GoogleFonts.playfairDisplay(fontSize: 26, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
                      child: const Text('Software Developer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.secondary)),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Specializing in end-to-end mobile application engineering and secure cloud architecture.\n\nSmart Society was built to modernize residential living, merging AI security with an elite, frictionless apartment administration.\n\n Guided by Prof. Jigar Dave',
                      textAlign: TextAlign.center, style: TextStyle(height: 1.5, color: AppTheme.textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity, height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, foregroundColor: AppTheme.textPrimary, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        icon: const Icon(Icons.email_outlined, size: 20),
                        label: const FittedBox(child: Text('milapdave6355@gmail.com', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                        onPressed: () async {
                          final Uri emailUri = Uri(scheme: 'mailto', path: 'milapdave6355@gmail.com', query: 'subject=Regarding Smart Society App');
                          try {
                            if (await canLaunchUrl(emailUri)) await launchUrl(emailUri);
                          } catch (e) {
                            debugPrint("Could not launch email client: $e");
                          }
                          if (context.mounted) Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ==========================================
  // PLAY STORE COMPLIANCE: DELETE ACCOUNT
  // ==========================================
  void _showDeleteAccountDialog(BuildContext context, User user) {
    final passwordController = TextEditingController();
    bool isProcessing = false;

    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: AppTheme.cardBg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.error, width: 2)),
            title: const Row(children: [Icon(Icons.warning, color: AppTheme.error), SizedBox(width: 10), Text("Delete Account", style: TextStyle(color: AppTheme.error, fontSize: 18, fontWeight: FontWeight.bold))]),
            content: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("WARNING: This will permanently eradicate your profile and permissions from the database. Re-authenticate to confirm.", style: TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                const SizedBox(height: 15),
                TextField(
                  controller: passwordController, obscureText: true, style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: "Current Password", prefixIcon: const Icon(Icons.lock, color: AppTheme.error),
                    filled: true, fillColor: AppTheme.background,
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.error)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.error, width: 2)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: isProcessing ? null : () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                onPressed: isProcessing ? null : () async {
                  if (passwordController.text.isEmpty) return;
                  setDialogState(() => isProcessing = true);
                  try {
                    AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: passwordController.text);
                    await user.reauthenticateWithCredential(credential);

                    await FirebaseFirestore.instance.collection('users').doc(user.uid).delete();
                    await user.delete();
                    if (mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const LoginScreen()), (route) => false);
                  } catch (e) {
                    setDialogState(() => isProcessing = false);
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authentication Failed.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
                  }
                },
                child: isProcessing ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2)) : const Text("DELETE DATA", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              )
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 80,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(1.2),
              decoration: BoxDecoration(gradient: AppTheme.goldGradient, shape: BoxShape.circle, boxShadow: const [AppTheme.glowEffect]),
              child: Image.asset('assets/images/logo.png', width: 50, height: 50),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                    child: Text("Smart Society", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
                  ),
                  const Text("PREMIUM SYSTEM", style: TextStyle(color: AppTheme.textMuted, fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').where('uid', isEqualTo: user?.uid).limit(1).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                final userData = snapshot.data!.docs.first.data() as Map<String, dynamic>;

                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: IconButton(
                    icon: const Icon(Icons.settings, color: AppTheme.primary, size: 28),
                    tooltip: "System Settings",
                    onPressed: () => _showSettingsMenu(context, userData), // Pass dynamic user data
                  ),
                );
              }
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('users').where('uid', isEqualTo: user?.uid).limit(1).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("User profile not linked. Contact Administration.", style: TextStyle(color: AppTheme.textMuted)));

          final userDoc = snapshot.data!.docs.first;
          final userData = userDoc.data() as Map<String, dynamic>;
          final String name = userData['name'] ?? "User";
          final String role = userData['role'] ?? 'resident';
          final String flat = "${userData['wing'] ?? ''}-${userData['flatNumber'] ?? ''}";
          final String currentStatus = userData['status'] ?? 'Left';
          final String orgId = userData['org_id'] ?? ''; // FETCH ORG_ID

          return Stack(
            children: [
              _buildNoticeListener(orgId),
              if (role == 'resident') _buildVisitorListener(flat, orgId),

              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("Welcome, $name", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary), overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(role == 'SUPER_ADMIN' ? "Role: Administrator" : role == 'guard' ? "Role: Security Guard" : "Flat: $flat", style: const TextStyle(fontSize: 14, color: AppTheme.textMuted)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            if (role == 'resident')
                              Column(
                                children: [
                                  Switch(
                                    value: currentStatus == 'Inside', activeColor: AppTheme.primary, activeTrackColor: AppTheme.primary.withOpacity(0.3), inactiveThumbColor: AppTheme.textMuted, inactiveTrackColor: AppTheme.cardBg,
                                    onChanged: (bool value) async {
                                      await FirebaseFirestore.instance.collection('users').doc(userDoc.id).update({'status': value ? 'Inside' : 'Left'});
                                    },
                                  ),
                                  Text(currentStatus == 'Inside' ? "At Home" : "Away", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: currentStatus == 'Inside' ? AppTheme.success : AppTheme.textMuted))
                                ],
                              ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: role == 'SUPER_ADMIN' ? _buildAdminUI(context, orgId) : role == 'guard' ? _buildGuardUI(context, orgId) : _buildResidentUI(context, userData, orgId),
                      ),

                      Container(
                        width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 15), margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
                        decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.verified_user, color: AppTheme.success, size: 16),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text("AI BASED SYSTEM • ENCRYPTED", style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
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
          );
        },
      ),
    );
  }

  Widget _buildNoticeListener(String orgId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('notices').where('org_id', isEqualTo: orgId).orderBy('createdAt', descending: true).limit(1).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first;
          if (_lastNoticeId != doc.id) {
            _lastNoticeId = doc.id;
            _newNoticeHighlight = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("📢 NOTICE: ${doc['title']}", style: const TextStyle(color: AppTheme.background)), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 3), backgroundColor: AppTheme.primary),
              );
              if (mounted) setState(() {});
            });
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildVisitorListener(String flat, String orgId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('visitors').where('org_id', isEqualTo: orgId).where('flatTarget', isEqualTo: flat).where('status', isEqualTo: 'Pending').snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final pendingDocs = snapshot.data!.docs;

        if (_activePopupVisitorId != null && pendingDocs.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_activePopupVisitorId != null && mounted) {
              _activePopupVisitorId = null;
              Navigator.of(context, rootNavigator: true).pop();
            }
          });
        }

        if (pendingDocs.isNotEmpty) {
          final doc = pendingDocs.first;
          if (_activePopupVisitorId != doc.id) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _showGateIntercomPopup(context, doc);
            });
          }
        }
        return const SizedBox.shrink();
      },
    );
  }

  void _showGateIntercomPopup(BuildContext context, DocumentSnapshot visitorDoc) {
    if (_activePopupVisitorId == visitorDoc.id) return;
    _activePopupVisitorId = visitorDoc.id;

    final data = visitorDoc.data() as Map<String, dynamic>;
    final String base64Photo = data['photoBase64'] ?? '';
    final String name = data['name'] ?? 'Unknown';
    final String purpose = data['purpose'] ?? 'General Visit';

    showDialog(
      context: context, barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppTheme.primary, width: 2)),
          title: const Row(
            children: [
              Icon(Icons.notification_important, color: AppTheme.warning), SizedBox(width: 10),
              Text("GATE APPROVAL REQUIRED", style: TextStyle(color: AppTheme.warning, fontSize: 14, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (base64Photo.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    base64Decode(base64Photo.replaceAll(RegExp(r'\s+'), '')), height: 150, width: 150, fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => const Icon(Icons.person, size: 100, color: AppTheme.textMuted),
                  ),
                ),
              const SizedBox(height: 15),
              Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              Text("Purpose: $purpose", style: const TextStyle(color: AppTheme.primary, fontSize: 14)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              icon: const Icon(Icons.close, color: AppTheme.background), label: const Text("DENY", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final docId = visitorDoc.id;
                _activePopupVisitorId = null;
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                await FirebaseFirestore.instance.collection('visitors').doc(docId).update({'status': 'Denied'});
              },
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
              icon: const Icon(Icons.check, color: AppTheme.background), label: const Text("ALLOW", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final docId = visitorDoc.id;
                _activePopupVisitorId = null;
                if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
                await FirebaseFirestore.instance.collection('visitors').doc(docId).update({'status': 'Inside'});
              },
            ),
          ],
        ),
      ),
    ).then((_) => _activePopupVisitorId = null);
  }

  int _getCrossAxisCount(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width > 900) return 4;
    if (width > 600) return 3;
    return 2;
  }

  Widget _buildAdminUI(BuildContext context, String orgId) {
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      crossAxisCount: _getCrossAxisCount(context),
      crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.85,
      children: [
        _buildMenuCard(context, "Manage Guards", Icons.security, 'admin_guards', {}, orgId),
        _buildMenuCard(context, "Billing & Ledger", Icons.account_balance_wallet, 'admin_billing', {}, orgId),
        _buildMenuCard(context, "Post Notice", Icons.add_alert, 'admin_notices', {}, orgId),
        _buildMenuCard(context, "Visitor Vault", Icons.admin_panel_settings, 'admin_visitors', {}, orgId),
        _buildMenuCard(context, "Family Manager", Icons.home_work, 'admin_families', {}, orgId),
        _buildMenuCard(context, "All Complaints", Icons.report_problem, 'admin_complaints', {}, orgId),
      ],
    );
  }

  Widget _buildGuardUI(BuildContext context, String orgId) {
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      crossAxisCount: _getCrossAxisCount(context),
      crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.85,
      children: [
        _buildMenuCard(context, "Resident AI Scan", Icons.face_unlock_outlined, 'guard_ai_scan', {}, orgId),
        _buildMenuCard(context, "Gate Entry", Icons.door_front_door, 'guard_entry', {}, orgId),
        _buildMenuCard(context, "Visitors Inside", Icons.directions_walk, 'guard_list', {}, orgId),
        _buildMenuCard(context, "View Notices", Icons.campaign, 'view_notices', {}, orgId),
      ],
    );
  }

  Widget _buildResidentUI(BuildContext context, Map<String, dynamic> userData, String orgId) {
    return GridView.count(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      crossAxisCount: _getCrossAxisCount(context),
      crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 0.85,
      children: [
        _buildMenuCard(context, "My Visitors", Icons.people, 'res_visitors', userData, orgId),
        _buildMenuCard(context, "Maintenance", Icons.payments, 'res_maint', userData, orgId),
        _buildMenuCard(context, "Notice Board", Icons.assignment, 'view_notices', userData, orgId),
        _buildMenuCard(context, "Complaints", Icons.report_problem, 'res_complaints', userData, orgId),
      ],
    );
  }

  Widget _buildMenuCard(BuildContext context, String title, IconData icon, String action, Map<String, dynamic> userData, String orgId) {
    bool isNotice = action == 'view_notices' || action == 'admin_notices';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        if (isNotice) setState(() => _newNoticeHighlight = false);
        final flat = userData.isNotEmpty ? "${userData['wing']}-${userData['flatNumber']}" : "";

        if (action == 'admin_guards') Navigator.push(context, MaterialPageRoute(builder: (c) => GuardManagementScreen(orgId: orgId)));
        if (action == 'admin_families') Navigator.push(context, MaterialPageRoute(builder: (c) => FamilyManagementScreen(orgId: orgId)));
        if (action == 'guard_entry') Navigator.push(context, MaterialPageRoute(builder: (c) => GuardEntryScreen(orgId: orgId)));
        if (action == 'guard_list' || action == 'admin_visitors') Navigator.push(context, MaterialPageRoute(builder: (c) => VisitorListScreen(orgId: orgId)));
        if (action == 'view_notices' || action == 'admin_notices') Navigator.push(context, MaterialPageRoute(builder: (c) => NoticeBoardScreen(orgId: orgId)));
        if (action == 'res_visitors') Navigator.push(context, MaterialPageRoute(builder: (c) => VisitorLogScreen(residentFlat: flat, orgId: orgId)));
        if (action == 'res_maint') Navigator.push(context, MaterialPageRoute(builder: (c) => MaintenanceScreen(residentFlat: flat, orgId: orgId)));
        if (action == 'res_complaints') Navigator.push(context, MaterialPageRoute(builder: (c) => ComplaintListScreen(residentFlat: flat, orgId: orgId)));
        if (action == 'admin_billing') Navigator.push(context, MaterialPageRoute(builder: (c) => AdminBillingScreen(orgId: orgId)));
        if (action == 'admin_complaints') Navigator.push(context, MaterialPageRoute(builder: (c) => AdminComplaintListScreen(orgId: orgId)));
        if (action == 'guard_ai_scan') Navigator.push(context, MaterialPageRoute(builder: (c) => GuardResidentScannerScreen(orgId: orgId)));
      },
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: (isNotice && _newNoticeHighlight) ? AppTheme.primary : AppTheme.borderHalf,
              width: (isNotice && _newNoticeHighlight) ? 2 : 1
          ),
          boxShadow: (isNotice && _newNoticeHighlight) ? [AppTheme.glowEffect] : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppTheme.background.withOpacity(0.5), shape: BoxShape.circle, border: Border.all(color: AppTheme.borderHalf)),
              child: Icon(icon, size: 36, color: AppTheme.primary),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}