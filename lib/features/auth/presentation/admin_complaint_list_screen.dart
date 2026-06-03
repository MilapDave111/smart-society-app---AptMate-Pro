import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../theme/app_theme.dart';

class AdminComplaintListScreen extends StatelessWidget {
  final String orgId;
  const AdminComplaintListScreen({super.key, required this.orgId});

  void _updateStatus(String docId, String currentStatus) async {
    String newStatus = currentStatus == 'Open' ? 'In Progress' : (currentStatus == 'In Progress' ? 'Resolved' : 'Open');
    await FirebaseFirestore.instance.collection('complaints').doc(docId).update({'status': newStatus});
  }

  void _deleteComplaint(String docId) async {
    await FirebaseFirestore.instance.collection('complaints').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    // RESPONSIVE SCREEN WIDTH MEASUREMENT
    double screenWidth = MediaQuery.of(context).size.width;
    bool isDesktop = screenWidth > 800;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text("Global Complaints", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // SCOPED QUERY: Only fetch complaints for this specific organization
        stream: FirebaseFirestore.instance.collection('complaints')
            .where('org_id', isEqualTo: orgId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No complaints found.", style: TextStyle(color: AppTheme.textMuted)));

          final docs = snapshot.data!.docs;

          // RESPONSIVE WRAPPER: Centers the list and prevents infinite stretching on desktop
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: ListView.builder(
                padding: EdgeInsets.all(isDesktop ? 30 : 20),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final Timestamp? time = data['createdAt'];
                  final String dateStr = time != null ? DateFormat('dd MMM, hh:mm a').format(time.toDate()) : "Unknown";
                  final String status = data['status'] ?? "Open";
                  final String flat = data['flatTarget'] ?? "Unknown Flat";

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(data['title'] ?? 'Untitled', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold))),
                          InkWell(
                            onTap: () => _updateStatus(docs[index].id, status),
                            child: _buildStatusBadge(status),
                          ),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 10.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Flat: $flat", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 4),
                            Text(data['description'] ?? '', style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.4)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(dateStr, style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 12)),
                                InkWell(onTap: () => _deleteComplaint(docs[index].id), child: const Icon(Icons.delete_outline, color: AppTheme.error, size: 20))
                              ],
                            )
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Resolved' ? AppTheme.success : (status == 'In Progress' ? AppTheme.primary : AppTheme.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text("$status (Tap to change)", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }
}