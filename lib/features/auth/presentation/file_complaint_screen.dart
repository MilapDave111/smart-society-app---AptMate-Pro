import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';

class FileComplaintScreen extends StatefulWidget {
  final String residentFlat;
  final String orgId; // INJECTED ORG_ID
  const FileComplaintScreen({super.key, required this.residentFlat, required this.orgId});

  @override
  State<FileComplaintScreen> createState() => _FileComplaintScreenState();
}

class _FileComplaintScreenState extends State<FileComplaintScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _category = 'Plumbing';
  bool _isSaving = false;

  void _submitComplaint() async {
    if (_titleController.text.isEmpty || _descController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("All fields are required.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('complaints').add({
        'org_id': widget.orgId, // STRICT ISOLATION
        'title': _titleController.text.trim(),
        'description': _descController.text.trim(),
        'category': _category,
        'flatTarget': widget.residentFlat,
        'status': 'Open',
        'createdAt': FieldValue.serverTimestamp(),
        'uid': FirebaseAuth.instance.currentUser?.uid,
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Complaint Registered", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Database Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: const Text("Lodge Complaint", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Ticket Details", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),

              _buildPremiumInput(controller: _titleController, label: "Subject / Title", icon: Icons.title),
              const SizedBox(height: 15),

              DropdownButtonFormField<String>(
                value: _category,
                dropdownColor: AppTheme.cardBg,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                decoration: InputDecoration(
                  labelText: "Category", labelStyle: const TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.category, color: AppTheme.textMuted, size: 20),
                  filled: true, fillColor: AppTheme.background,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                ),
                items: ['Plumbing', 'Electrical', 'Security', 'Cleaning', 'Other'].map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (val) => setState(() => _category = val!),
              ),
              const SizedBox(height: 15),

              _buildPremiumInput(controller: _descController, label: "Detailed Description", icon: Icons.description, maxLines: 4),
              const SizedBox(height: 25),

              InkWell(
                onTap: _isSaving ? null : _submitComplaint,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(gradient: AppTheme.goldGradient, borderRadius: BorderRadius.circular(12), boxShadow: const [AppTheme.glowEffect]),
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
      ),
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