import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class MaintenanceScreen extends StatefulWidget {
  final String residentFlat;
  final String orgId; // INJECTED ORG_ID
  const MaintenanceScreen({super.key, required this.residentFlat, required this.orgId});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  bool _isLoading = true;
  double _lastMonthLightBill = 0.0;
  String? _societyQrCode;

  @override
  void initState() {
    super.initState();
    _initializeLedger();
  }

  Future<void> _initializeLedger() async {
    try {
      DateTime now = DateTime.now();
      String currentMonthKey = "${now.month}-${now.year}";

      // SCOPED SETTINGS FETCH
      final settings = await FirebaseFirestore.instance.collection('settings').doc('${widget.orgId}_billing').get();
      double baseAmount = 0.0;
      if (settings.exists) {
        baseAmount = (settings.data()?['baseMaintenance'] ?? 0.0).toDouble();
        _societyQrCode = settings.data()?['qrCodeBase64'];
      }

      final existingMaint = await FirebaseFirestore.instance
          .collection('bills')
          .where('org_id', isEqualTo: widget.orgId) // STRICT ISOLATION
          .where('flatTarget', isEqualTo: widget.residentFlat)
          .where('type', isEqualTo: 'Maintenance')
          .where('monthKey', isEqualTo: currentMonthKey)
          .get();

      if (existingMaint.docs.isEmpty && baseAmount > 0) {
        DateTime dueDate = DateTime(now.year, now.month, 30);
        await FirebaseFirestore.instance.collection('bills').add({
          'org_id': widget.orgId,
          'type': 'Maintenance', 'baseAmount': baseAmount, 'flatTarget': widget.residentFlat,
          'status': 'Pending', 'transactionId': '', 'createdAt': FieldValue.serverTimestamp(),
          'dueDate': Timestamp.fromDate(dueDate), 'monthKey': currentMonthKey,
        });
      }

      DateTime lastMonthDate = DateTime(now.year, now.month - 1, 1);
      String lastMonthKey = "${lastMonthDate.month}-${lastMonthDate.year}";
      final lastLightBill = await FirebaseFirestore.instance
          .collection('bills')
          .where('org_id', isEqualTo: widget.orgId)
          .where('flatTarget', isEqualTo: widget.residentFlat)
          .where('type', isEqualTo: 'Light Bill')
          .where('monthKey', isEqualTo: lastMonthKey)
          .get();

      if (lastLightBill.docs.isNotEmpty) {
        _lastMonthLightBill = (lastLightBill.docs.first.data()['baseAmount'] as num).toDouble();
      }

      if (now.day >= 25 && now.day <= 30) {
        _checkPendingAndPopup();
      }
    } catch (e) {
      debugPrint("Ledger Init Error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _checkPendingAndPopup() async {
    final pending = await FirebaseFirestore.instance.collection('bills')
        .where('org_id', isEqualTo: widget.orgId)
        .where('flatTarget', isEqualTo: widget.residentFlat)
        .where('status', isEqualTo: 'Pending').get();

    if (pending.docs.isNotEmpty && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.warning)),
            title: const Text("Payment Reminder", style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.bold)),
            content: const Text("You have pending bills. Please clear them before the 30th to avoid a 2% late penalty.", style: TextStyle(color: AppTheme.textPrimary)),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Acknowledge", style: TextStyle(color: AppTheme.primary)))],
          ),
        );
      });
    }
  }

  double _calculateFinalAmount(double baseAmount, Timestamp dueDate) {
    DateTime due = dueDate.toDate();
    DateTime now = DateTime.now();
    if (now.isAfter(due) && now.day != due.day) {
      return baseAmount + (baseAmount * 0.02);
    }
    return baseAmount;
  }

  void _showPaymentDialog(BuildContext context, String docId, double amountDue) {
    final utrController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: AppTheme.border)),
        title: const Text("Secure UPI Payment", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Scan QR with GPay/PhonePe.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
              const SizedBox(height: 15),

              Container(
                height: 200, width: 200,
                decoration: BoxDecoration(color: AppTheme.textPrimary, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary, width: 2)),
                child: _societyQrCode != null && _societyQrCode!.isNotEmpty
                    ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(base64Decode(_societyQrCode!), fit: BoxFit.contain))
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.qr_code_2, size: 80, color: Colors.black54), Text("No QR Found", style: TextStyle(color: Colors.black54))]),
              ),

              const SizedBox(height: 15),
              Text("Total Due: ₹${amountDue.toStringAsFixed(2)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: AppTheme.error)),
              const SizedBox(height: 20),

              TextField(
                controller: utrController,
                keyboardType: TextInputType.number,
                maxLength: 12,
                style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  labelText: "Enter 12-Digit UTR",
                  labelStyle: const TextStyle(color: AppTheme.textMuted),
                  filled: true,
                  fillColor: AppTheme.background,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                ),
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: AppTheme.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: AppTheme.background, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              if (utrController.text.length < 12) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid UTR. Must be 12 digits.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
                return;
              }
              await FirebaseFirestore.instance.collection('bills').doc(docId).update({'status': 'Under Review', 'transactionId': utrController.text.trim()});
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text("Submit Verification"),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(backgroundColor: AppTheme.background, body: Center(child: CircularProgressIndicator(color: AppTheme.primary)));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text("Financial Ledger", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('bills')
            .where('org_id', isEqualTo: widget.orgId) // STRICT ISOLATION
            .where('flatTarget', isEqualTo: widget.residentFlat)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", textAlign: TextAlign.center, style: const TextStyle(color: AppTheme.error)));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No bills found.", style: TextStyle(color: AppTheme.textMuted)));

          final docs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final String type = data['type'] ?? 'Bill';
              final double baseAmount = (data['baseAmount'] as num).toDouble();
              final Timestamp dueDate = data['dueDate'];
              final String status = data['status'] ?? 'Pending';

              double finalAmount = status == 'Pending' ? _calculateFinalAmount(baseAmount, dueDate) : baseAmount;
              bool hasPenalty = finalAmount > baseAmount;

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: AppTheme.cardGradient,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: status == 'Paid' ? AppTheme.success.withOpacity(0.5) : AppTheme.borderHalf, width: status == 'Paid' ? 1.5 : 1),
                  boxShadow: status == 'Paid' ? [BoxShadow(color: AppTheme.success.withOpacity(0.1), blurRadius: 10)] : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(type, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                        _buildStatusBadge(status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text("Due Date: ${dueDate.toDate().day}/${dueDate.toDate().month}/${dueDate.toDate().year}", style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 13)),
                    if (hasPenalty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Text("⚠️ 2% Late Fee Applied (Past Due)", style: TextStyle(color: AppTheme.error, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),

                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("₹${finalAmount.toStringAsFixed(2)}", style: const TextStyle(color: AppTheme.primary, fontSize: 26, fontWeight: FontWeight.bold)),
                        if (status == 'Pending')
                          ElevatedButton(
                            onPressed: () => _showPaymentDialog(context, docs[index].id, finalAmount),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary, foregroundColor: AppTheme.background,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Pay Now", style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),

                    if (type == 'Light Bill' && data.containsKey('societyAverage')) ...[
                      const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Divider(color: AppTheme.border)),
                      const Text("Energy Usage Analytics", style: TextStyle(fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                      const SizedBox(height: 20),
                      _buildAnalyticsChart(baseAmount, _lastMonthLightBill, (data['societyAverage'] as num).toDouble()),
                    ]
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Paid' ? AppTheme.success : (status == 'Under Review' ? AppTheme.secondary : AppTheme.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withOpacity(0.5))),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10, letterSpacing: 1.0)),
    );
  }

  Widget _buildAnalyticsChart(double current, double lastMonth, double average) {
    double maxAmount = [current, lastMonth, average].reduce((a, b) => a > b ? a : b);
    if (maxAmount == 0) maxAmount = 1;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (lastMonth > 0) _buildBar((lastMonth / maxAmount) * 100, AppTheme.border, "Last Mth\n₹${lastMonth.toInt()}"),
        _buildBar((current / maxAmount) * 100, AppTheme.primary, "Current\n₹${current.toInt()}"),
        _buildBar((average / maxAmount) * 100, AppTheme.secondary, "Society Avg\n₹${average.toInt()}"),
      ],
    );
  }

  Widget _buildBar(double height, Color color, String label) {
    return Column(
      children: [
        Container(
          height: height, width: 40,
          decoration: BoxDecoration(color: color, borderRadius: const BorderRadius.vertical(top: Radius.circular(6)), boxShadow: color == AppTheme.primary ? [AppTheme.glowEffect] : []),
        ),
        const SizedBox(height: 8),
        Text(label, textAlign: TextAlign.center, style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    );
  }
}