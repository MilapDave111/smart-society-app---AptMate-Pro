import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';

class VisitorLogScreen extends StatelessWidget {
  final String residentFlat;
  final String orgId; // INJECTED ORG_ID
  const VisitorLogScreen({super.key, required this.residentFlat, required this.orgId});

  void _showImageDialog(BuildContext context, String base64String, String name) {
    try {
      final cleanBase64 = base64String.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(cleanBase64);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppTheme.cardBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.border)),
          title: Text("Biometric Scan: $name", style: const TextStyle(color: AppTheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Padding(
                padding: EdgeInsets.all(20.0),
                child: Icon(Icons.broken_image, color: AppTheme.error, size: 50),
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close", style: TextStyle(color: AppTheme.primary)))
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Image data is corrupted.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    }
  }

  Widget _buildAvatar(Map<String, dynamic> data) {
    final String? base64Photo = data['photoBase64'];
    final String fallbackLetter = data['name'] != null && data['name'].toString().isNotEmpty ? data['name'][0].toUpperCase() : "V";
    final fallbackWidget = Center(child: Text(fallbackLetter, style: const TextStyle(color: AppTheme.primary, fontSize: 20, fontWeight: FontWeight.bold)));

    if (base64Photo == null || base64Photo.isEmpty) {
      return fallbackWidget;
    }

    try {
      final cleanBase64 = base64Photo.replaceAll(RegExp(r'\s+'), '');
      final bytes = base64Decode(cleanBase64);

      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        width: 50,
        height: 50,
        errorBuilder: (context, error, stackTrace) => fallbackWidget,
      );
    } catch (e) {
      debugPrint("Base64 Decode Error: $e");
      return fallbackWidget;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text("Access Logs", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text("Decrypted Records for Flat $residentFlat", style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('visitors')
                  .where('org_id', isEqualTo: orgId) // STRICT ISOLATION
                  .where('flatTarget', isEqualTo: residentFlat)
                  .orderBy('entryTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)));
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No visitors recorded for this flat.", style: TextStyle(color: AppTheme.textMuted)));

                final docs = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;

                    final Timestamp? timestamp = data['entryTime'] as Timestamp?;
                    final DateTime entry = timestamp != null ? timestamp.toDate() : DateTime.now();
                    final String status = data['status'] ?? "Left";
                    final String? base64Photo = data['photoBase64'];

                    return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: GestureDetector(
                          onTap: () {
                            if (base64Photo != null && base64Photo.isNotEmpty) {
                              _showImageDialog(context, base64Photo, data['name'] ?? 'Visitor');
                            }
                          },
                          child: Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(color: AppTheme.background, shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withOpacity(0.5))),
                            child: ClipOval(
                              child: _buildAvatar(data),
                            ),
                          ),
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
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time, size: 14, color: AppTheme.textMuted), const SizedBox(width: 4),
                                  Text(DateFormat('dd MMM, hh:mm a').format(entry), style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  data['purpose'] ?? '',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.bold),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Inside' ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(status, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}