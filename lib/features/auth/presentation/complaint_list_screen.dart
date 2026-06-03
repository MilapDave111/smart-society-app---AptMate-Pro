import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';

class ComplaintListScreen extends StatefulWidget {
  final String residentFlat;
  final String orgId; // INJECTED ORG_ID
  const ComplaintListScreen({super.key, required this.residentFlat, required this.orgId});

  @override
  State<ComplaintListScreen> createState() => _ComplaintListScreenState();
}

class _ComplaintListScreenState extends State<ComplaintListScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  bool _isSaving = false;
  bool _showAddForm = false; // Toggles between Ticket List and New Ticket Form

  void _submitComplaint() async {
    if (_titleController.text.isEmpty || _descController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please fill all fields", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('complaints').add({
        'org_id': widget.orgId, // STRICT ISOLATION
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'flatTarget': widget.residentFlat,
        'status': 'Open',
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _titleController.clear();
        _descController.clear();

        // Drop user back to the list view immediately upon success
        setState(() => _showAddForm = false);

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ticket Raised Successfully", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _deleteComplaint(String docId) async {
    await FirebaseFirestore.instance.collection('complaints').doc(docId).delete();
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
              _showAddForm ? "Raise Ticket" : "Helpdesk",
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
                        Icon(Icons.add_task, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text("New Ticket", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800), // Enforce tablet responsiveness
            child: _showAddForm ? _buildFormView() : _buildListView(),
          ),
        ),
      ),
    );
  }

  // --- PREMIUM SUBMIT FORM VIEW ---
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
            const Text("Raise a New Ticket", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _titleController, label: "Subject", icon: Icons.title),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _descController, label: "Detailed Description", icon: Icons.notes, maxLines: 3),
            const SizedBox(height: 20),
            InkWell(
              onTap: _isSaving ? null : _submitComplaint,
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
                  child: _isSaving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("Submit Ticket", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- TICKET LIST VIEW ---
  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Text("My Active Tickets", style: TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('complaints')
                .where('org_id', isEqualTo: widget.orgId) // SCOPED
                .where('flatTarget', isEqualTo: widget.residentFlat)
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No active tickets.", style: TextStyle(color: AppTheme.textMuted)));

              final docs = snapshot.data!.docs;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final Timestamp? time = data['createdAt'];
                  final String dateStr = time != null ? DateFormat('dd MMM, hh:mm a').format(time.toDate()) : "Just now";
                  final String status = data['status'] ?? "Open";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: Text(
                                  data['title'] ?? 'Untitled',
                                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)
                              )
                          ),
                          const SizedBox(width: 10),
                          _buildStatusBadge(status),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['description'] ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.4)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(dateStr, style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontSize: 12)),
                                InkWell(onTap: () => _deleteComplaint(docs[index].id), child: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20))
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        )
      ],
    );
  }

  // --- UI HELPERS ---

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Resolved' ? AppTheme.success : (status == 'In Progress' ? AppTheme.primary : AppTheme.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
    );
  }

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, int maxLines = 1}) {
    return TextField(
      controller: controller, maxLines: maxLines, style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: AppTheme.textMuted),
        prefixIcon: maxLines == 1 ? Icon(icon, color: AppTheme.textMuted, size: 20) : null,
        filled: true, fillColor: AppTheme.background,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }
}