import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http; // REQUIRED FOR FCM ALERT TRIPWIRE
import '../../../theme/app_theme.dart';
import 'visitor_log_screen.dart'; // Reroutes Admin to the single flat view

class VisitorListScreen extends StatefulWidget {
  final String orgId;
  const VisitorListScreen({super.key, required this.orgId});

  @override
  State<VisitorListScreen> createState() => _VisitorListScreenState();
}

class _VisitorListScreenState extends State<VisitorListScreen> {
  DateTime? _selectedDate;
  String _selectedType = 'All';
  String _userRole = 'resident';

  final List<String> _filterOptions = ['All', 'Delivery (Amazon/Flipkart)', 'Guest / Relative', 'Maintenance / Plumber', 'Cab / Taxi', 'Maid / Helper','Property Agent', 'Other'];

  @override
  void initState() {
    super.initState();
    _checkRole();
  }

  void _checkRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').where('uid', isEqualTo: user.uid).limit(1).get();
    if (doc.docs.isNotEmpty && mounted) {
      setState(() {
        _userRole = doc.docs.first.data()['role'] ?? 'resident';
      });
    }
  }

  // ==========================================
  // THE TRIPWIRE PROTOCOL LOGIC (PRIVATE ALERT ONLY)
  // ==========================================
  void _showAdminUnlockDialog(String flatId, String? residentFcmToken) {
    final adminPasswordController = TextEditingController();
    final reasonController = TextEditingController();
    bool isUnlocking = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.error, width: 2)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.error),
                  SizedBox(width: 10),
                  Text("EMERGENCY OVERRIDE", style: TextStyle(color: AppTheme.error, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("You are attempting to bypass privacy controls to view the visitor logs for Flat $flatId.", style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                    const SizedBox(height: 10),
                    const Text("WARNING: Executing this override will instantly alert the resident of your access.", style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 20),

                    TextField(
                      controller: reasonController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: "Emergency Reason (Required)",
                        labelStyle: const TextStyle(color: AppTheme.textMuted),
                        prefixIcon: const Icon(Icons.edit_note, color: AppTheme.textMuted),
                        filled: true, fillColor: AppTheme.background,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.warning, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 15),

                    TextField(
                      controller: adminPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        labelText: "Enter Admin Password to Unlock",
                        labelStyle: const TextStyle(color: AppTheme.textMuted),
                        prefixIcon: const Icon(Icons.lock, color: AppTheme.textMuted),
                        filled: true, fillColor: AppTheme.background,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.error)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.error, width: 2)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isUnlocking ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
                  onPressed: isUnlocking ? null : () async {
                    if (adminPasswordController.text.isEmpty || reasonController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Both Reason and Password are required.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
                      return;
                    }

                    setDialogState(() => isUnlocking = true);
                    final String overrideReason = reasonController.text.trim();

                    try {
                      final user = FirebaseAuth.instance.currentUser!;
                      // 1. Mathematically Re-Authenticate the Admin
                      AuthCredential credential = EmailAuthProvider.credential(email: user.email!, password: adminPasswordController.text);
                      await user.reauthenticateWithCredential(credential);

                      // 2. Ping FCM Tripwire direct to the resident's phone (Private Alert)
                      if (residentFcmToken != null && residentFcmToken.isNotEmpty) {
                        await http.post(
                          Uri.parse('https://aptmate-backend-server.onrender.com/send-gate-alert'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({
                            'token': residentFcmToken,
                            'title': 'SECURITY ALERT: Privacy Override',
                            'body': 'The Administrator bypassed your privacy controls. Reason: $overrideReason',
                            'visitorId': 'system_audit'
                          }),
                        );
                      }

                      // 3. Decrypt and Navigate to the Logs
                      if (mounted) {
                        Navigator.pop(context); // Close Dialog
                        Navigator.push(context, MaterialPageRoute(builder: (c) => VisitorLogScreen(residentFlat: flatId, orgId: widget.orgId)));
                      }

                    } catch (e) {
                      setDialogState(() => isUnlocking = false);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Authentication Failed. Access Denied.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
                    }
                  },
                  child: isUnlocking
                      ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("Unlock & Alert", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
                )
              ],
            );
          }
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text(
          _userRole == 'SUPER_ADMIN' ? "Locked Vaults" : "Current Visitors",
          style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Filter Bar is completely hidden from Admin to enforce Vault View
          if (_userRole != 'SUPER_ADMIN') _buildPremiumFilterBar(),

          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                  _userRole == 'SUPER_ADMIN' ? "Select a flat to initiate Break-Glass protocol" : "Visitors Inside Premises",
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)
              ),
            ),
          ),

          // Routing logic: Admins get the Vault, Guards get the Raw List
          Expanded(child: _userRole == 'SUPER_ADMIN' ? _buildAdminVaultList() : _buildVisitorList()),
        ],
      ),
    );
  }

  // ==========================================
  // THE VAULT VIEW (ADMIN ONLY)
  // ==========================================
  Widget _buildAdminVaultList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users')
          .where('org_id', isEqualTo: widget.orgId) // STRICT ISOLATION
          .where('role', isEqualTo: 'resident')
          .orderBy('wing').orderBy('flatNumber').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", style: const TextStyle(color: AppTheme.error)));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No residents registered.", style: TextStyle(color: AppTheme.textMuted)));

        final docs = snapshot.data!.docs;

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final String flatDisplay = "${data['wing']}-${data['flatNumber']}";
            final String? token = data['fcmToken'];

            return Container(
              margin: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showAdminUnlockDialog(flatDisplay, token),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  leading: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primary.withOpacity(0.3))),
                    child: const Icon(Icons.lock, color: AppTheme.error),
                  ),
                  title: Text("Flat $flatDisplay", style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: const Text("Data Encrypted. Tap to Unlock.", style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: AppTheme.primary),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ==========================================
  // THE RAW FEED (GUARD ONLY)
  // ==========================================
  Widget _buildPremiumFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderHalf),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Filter Logs", style: TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                flex: 1,
                child: InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: DateTime.now(),
                      firstDate: DateTime(2024),
                      lastDate: DateTime.now(),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(context).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: AppTheme.primary,
                              onPrimary: AppTheme.background,
                              surface: AppTheme.cardBg,
                              onSurface: AppTheme.textPrimary,
                            ),
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (date != null) setState(() => _selectedDate = date);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.calendar_today, color: AppTheme.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _selectedDate == null ? "All Dates" : DateFormat('dd MMM').format(_selectedDate!),
                            style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_selectedDate != null)
                          GestureDetector(
                            onTap: () => setState(() => _selectedDate = null),
                            child: const Icon(Icons.close, color: AppTheme.error, size: 16),
                          )
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    border: Border.all(color: AppTheme.border),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedType,
                      isExpanded: true,
                      dropdownColor: AppTheme.cardBg,
                      icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                      items: _filterOptions.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                      onChanged: (val) => setState(() => _selectedType = val!),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVisitorList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('visitors')
          .where('org_id', isEqualTo: widget.orgId) // STRICT ISOLATION
          .orderBy('entryTime', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text("Database Error:\n${snapshot.error}", style: const TextStyle(color: AppTheme.error))));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

        final allDocs = snapshot.data!.docs;

        final filteredDocs = allDocs.where((docSnapshot) {
          final data = docSnapshot.data() as Map<String, dynamic>;
          final status = data['status'] ?? "Left";
          final purpose = data['purpose'] ?? "";

          if (_userRole == 'guard' && status != 'Inside') return false;
          if (_selectedType != 'All' && purpose != _selectedType) return false;

          if (_selectedDate != null) {
            if (!data.containsKey('entryTime') || data['entryTime'] == null) return false;
            DateTime entry = (data['entryTime'] as Timestamp).toDate();
            if (entry.year != _selectedDate!.year || entry.month != _selectedDate!.month || entry.day != _selectedDate!.day) {
              return false;
            }
          }
          return true;
        }).toList();

        if (filteredDocs.isEmpty) return const Center(child: Text("No visitor records found matching criteria.", style: TextStyle(color: AppTheme.textMuted)));

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          itemCount: filteredDocs.length,
          itemBuilder: (context, index) {
            final docSnapshot = filteredDocs[index];
            final data = docSnapshot.data() as Map<String, dynamic>;
            final id = docSnapshot.id;

            final DateTime entry = data.containsKey('entryTime') && data['entryTime'] != null
                ? (data['entryTime'] as Timestamp).toDate()
                : DateTime.now();

            final String status = data['status'] ?? "Left";
            final String? base64Str = data['photoBase64'];
            final bool hasValidImage = base64Str != null && base64Str.isNotEmpty;

            return Container(
              margin: const EdgeInsets.only(bottom: 15),
              decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
              child: ListTile(
                contentPadding: const EdgeInsets.all(16),
                leading: CircleAvatar(
                  radius: 25, backgroundColor: AppTheme.borderHalf,
                  backgroundImage: hasValidImage ? MemoryImage(base64Decode(base64Str)) : null,
                  child: hasValidImage ? null : const Icon(Icons.person, color: AppTheme.textMuted),
                ),
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(data['name'] ?? 'Unknown', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16), overflow: TextOverflow.ellipsis)),
                    _buildStatusBadge(status),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.meeting_room, size: 14, color: AppTheme.textMuted), const SizedBox(width: 4),
                          Text("Flat: ${data['flatTarget'] ?? 'Unknown'}", style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted), const SizedBox(width: 4),
                              Text(DateFormat('jm').format(entry), style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 12)),
                            ],
                          ),
                          Text(data['purpose'] ?? '', style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                        ],
                      ),

                      if (_userRole == 'guard' && status == 'Inside') ...[
                        const SizedBox(height: 15),
                        InkWell(
                          onTap: () => _checkoutVisitor(id),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.primary)),
                            child: const Center(child: Text("Mark as Exited", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold))),
                          ),
                        )
                      ]
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Inside' ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.5))),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }

  void _checkoutVisitor(String docId) async {
    await FirebaseFirestore.instance.collection('visitors').doc(docId).update({
      'status': 'Left',
      'exitTime': FieldValue.serverTimestamp(),
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Visitor Exited", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.textMuted));
  }
}