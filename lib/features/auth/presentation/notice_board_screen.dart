import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';
import 'package:http/http.dart' as http;

class NoticeBoardScreen extends StatefulWidget {
  final String orgId;
  const NoticeBoardScreen({super.key, required this.orgId});

  @override
  State<NoticeBoardScreen> createState() => _NoticeBoardScreenState();
}

class _NoticeBoardScreenState extends State<NoticeBoardScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  String _userRole = 'resident'; // Default until loaded
  bool _isLoadingRole = true;
  bool _isPosting = false;
  bool _showPostForm = false; // Toggles between List and Form view

  @override
  void initState() {
    super.initState();
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').where('uid', isEqualTo: user.uid).limit(1).get();
        if (doc.docs.isNotEmpty) {
          setState(() {
            _userRole = doc.docs.first.data()['role'] ?? 'resident';
          });
        }
      }
    } catch (e) {
      debugPrint("Error fetching role: $e");
    } finally {
      if (mounted) setState(() => _isLoadingRole = false);
    }
  }

  void _postNotice() async {
    if (_titleController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notice title is required", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning),
      );
      return;
    }

    setState(() => _isPosting = true);
    try {
      await FirebaseFirestore.instance.collection('notices').add({
        'org_id': widget.orgId, // STRICT ISOLATION
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'authorId': FirebaseAuth.instance.currentUser?.uid,
      });

      if (mounted) {
        _titleController.clear();
        _contentController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Notice Published Successfully", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success),
        );

        // Return to the list view immediately upon success
        setState(() => _showPostForm = false);

        try {
          final url = Uri.parse('https://aptmate-backend-server.onrender.com/send-broadcast-alert');
          await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'topic': 'all_notices_${widget.orgId}', // ISOLATED TOPIC
              'title': 'New Society Notice',
              'body': 'A new notice has been posted by the Admin. Open the app to read it.',
            }),
          );
        } catch (e) {
          debugPrint("Broadcast notification failed, but notice was saved: $e");
        }
      }
    } catch (e) {
      debugPrint("Error posting notice: $e");
    } finally {
      if (mounted) setState(() => _isPosting = false);
    }
  }

  void _deleteNotice(String docId) async {
    await FirebaseFirestore.instance.collection('notices').doc(docId).delete();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Notice Removed", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.textMuted),
      );
    }
  }

  void _handleBackPress() {
    if (_showPostForm) {
      setState(() => _showPostForm = false);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingRole) {
      return const Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_showPostForm) {
          setState(() => _showPostForm = false);
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
            _showPostForm ? "Draft Notice" : "Society Notices",
            style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 19.1, fontWeight: FontWeight.bold),
          ),
          actions: [
            // Only show the Post button if the user is an admin AND we are looking at the list
            if (_userRole == 'SUPER_ADMIN' && !_showPostForm) // Updated to SUPER_ADMIN
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _showPostForm = true),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.primary.withOpacity(0.5))
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add_alert, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text("Post Notice", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
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
            child: _showPostForm ? _buildAdminPostForm() : _buildListSection(),
          ),
        ),
      ),
    );
  }

  // --- ADMIN POST FORM ---
  Widget _buildAdminPostForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.cardGradient,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.borderHalf),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Draft New Notice", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            _buildPremiumInput(
                controller: _titleController,
                label: "Headline / Subject",
                icon: Icons.title
            ),
            const SizedBox(height: 15),

            _buildPremiumInput(
              controller: _contentController,
              label: "Detailed Message (Optional)",
              icon: Icons.subject,
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            InkWell(
              onTap: _isPosting ? null : _postNotice,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: AppTheme.goldGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [AppTheme.glowEffect],
                ),
                child: Center(
                  child: _isPosting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("Publish Broadcast", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- NOTICE LIST SECTION ---
  Widget _buildListSection() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text("Recent Announcements", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('notices')
                .where('org_id', isEqualTo: widget.orgId) // SCOPED
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No notices posted yet.", style: TextStyle(color: AppTheme.textMuted)));

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final Timestamp? time = data['createdAt'];
                  final String dateStr = time != null ? DateFormat('dd MMM yyyy, hh:mm a').format(time.toDate()) : "Just now";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                        color: AppTheme.cardBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.borderHalf),
                        boxShadow: const [
                          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                        ]
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: const BoxDecoration(
                            border: Border(left: BorderSide(color: AppTheme.primary, width: 4))
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    data['title'] ?? 'Untitled Notice',
                                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (_userRole == 'SUPER_ADMIN')
                                  InkWell(
                                    onTap: () => _deleteNotice(docs[index].id),
                                    child: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20),
                                  )
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dateStr,
                              style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontSize: 12),
                            ),
                            if (data['content'] != null && data['content'].toString().isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Divider(color: AppTheme.borderHalf),
                              const SizedBox(height: 8),
                              Text(
                                data['content'],
                                style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.5),
                              ),
                            ]
                          ],
                        ),
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

  // --- REUSABLE PREMIUM INPUT ---
  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppTheme.textMuted),
        prefixIcon: maxLines == 1 ? Icon(icon, color: AppTheme.textMuted, size: 20) : null,
        filled: true,
        fillColor: AppTheme.background,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }
}