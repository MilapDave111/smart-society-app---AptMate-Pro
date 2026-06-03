import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class AdminBillingScreen extends StatefulWidget {
  final String orgId;
  const AdminBillingScreen({super.key, required this.orgId});

  @override
  State<AdminBillingScreen> createState() => _AdminBillingScreenState();
}

class _AdminBillingScreenState extends State<AdminBillingScreen> {
  // GLOBAL SETTINGS CONTROLLERS
  final _globalMaintController = TextEditingController();
  String? _qrCodeBase64;
  final ImagePicker _picker = ImagePicker();
  bool _isSavingSettings = false;

  // CUSTOM INVOICE CONTROLLERS
  final _flatTargetController = TextEditingController();
  final _invoiceAmountController = TextEditingController();
  final _customReasonController = TextEditingController();
  String _invoiceType = 'Light Bill';
  bool _isGeneratingInvoice = false;

  // COMMON BILL CONTROLLERS
  final _commonAmountController = TextEditingController();
  final _commonReasonController = TextEditingController();
  bool _isGeneratingCommonBill = false;

  // AUTOCOMPLETE DATA
  List<String> _allFlats = [];

  @override
  void initState() {
    super.initState();
    _fetchFlatsAndSettings();
  }

  Future<void> _fetchFlatsAndSettings() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users')
          .where('org_id', isEqualTo: widget.orgId)
          .where('role', isEqualTo: 'resident').get();
      final flats = snapshot.docs.map((doc) => "${doc['wing']}-${doc['flatNumber']}").toSet().toList();

      final settingsDoc = await FirebaseFirestore.instance.collection('settings').doc('${widget.orgId}_billing').get();
      if (settingsDoc.exists && mounted) {
        _globalMaintController.text = (settingsDoc.data()?['baseMaintenance'] ?? 0).toString();
        _qrCodeBase64 = settingsDoc.data()?['qrCodeBase64'];
      }

      if (mounted) setState(() => _allFlats = flats);
    } catch (e) {
      debugPrint("Error fetching data: $e");
    }
  }

  // --- LOGIC: GLOBAL SETTINGS ---
  Future<void> _pickImage() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
      if (image != null) {
        final Uint8List bytes = await image.readAsBytes();
        setState(() {
          _qrCodeBase64 = base64Encode(bytes);
        });
      }
    } catch (e) {
      debugPrint("Image Picker Error: $e");
    }
  }

  void _saveGlobalMaintenance() async {
    if (_globalMaintController.text.isEmpty) return;

    setState(() => _isSavingSettings = true);
    try {
      await FirebaseFirestore.instance.collection('settings').doc('${widget.orgId}_billing').set({
        'baseMaintenance': double.parse(_globalMaintController.text.trim()),
        'qrCodeBase64': _qrCodeBase64,
        'org_id': widget.orgId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Global Settings & QR Code Updated!", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isSavingSettings = false);
    }
  }

  // --- LOGIC: CUSTOM INVOICE ---
  void _generateCustomInvoice() async {
    final amountText = _invoiceAmountController.text.trim();
    final flatTarget = _flatTargetController.text.trim().toUpperCase();

    if (flatTarget.isEmpty || amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Target Flat and Amount are required", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    bool requiresReason = _invoiceType == 'Penalty' || _invoiceType == 'Other';
    if (requiresReason && _customReasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("A reason/description is required for this invoice type", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    double? amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid numerical amount", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isGeneratingInvoice = true);
    try {
      DateTime now = DateTime.now();
      await FirebaseFirestore.instance.collection('bills').add({
        'org_id': widget.orgId,
        'type': _invoiceType,
        'baseAmount': amount,
        'flatTarget': flatTarget,
        'description': requiresReason ? _customReasonController.text.trim() : '',
        'status': 'Pending',
        'transactionId': '',
        'createdAt': FieldValue.serverTimestamp(),
        'dueDate': Timestamp.fromDate(DateTime(now.year, now.month, 30)),
        'monthKey': "${now.month}-${now.year}",
      });

      if (mounted) {
        _flatTargetController.clear(); _invoiceAmountController.clear(); _customReasonController.clear();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invoice Generated Successfully", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isGeneratingInvoice = false);
    }
  }

  // --- LOGIC: COMMON BILL ---
  void _generateCommonBill() async {
    final amountText = _commonAmountController.text.trim();
    final reasonText = _commonReasonController.text.trim();

    if (amountText.isEmpty || reasonText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Total Amount and Reason are required", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    double? totalAmount = double.tryParse(amountText);
    if (totalAmount == null || totalAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid total amount", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    setState(() => _isGeneratingCommonBill = true);

    try {
      final snapshot = await FirebaseFirestore.instance.collection('users')
          .where('org_id', isEqualTo: widget.orgId)
          .where('role', isEqualTo: 'resident').get();

      if (snapshot.docs.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No registered families found to split the bill.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
        return;
      }

      int familyCount = snapshot.docs.length;
      double splitAmount = totalAmount / familyCount;

      WriteBatch batch = FirebaseFirestore.instance.batch();
      DateTime now = DateTime.now();
      String currentMonthKey = "${now.month}-${now.year}";

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final String flatTarget = "${data['wing']}-${data['flatNumber']}";

        DocumentReference billRef = FirebaseFirestore.instance.collection('bills').doc();
        batch.set(billRef, {
          'org_id': widget.orgId,
          'type': 'Common Bill',
          'baseAmount': double.parse(splitAmount.toStringAsFixed(2)),
          'flatTarget': flatTarget,
          'description': reasonText,
          'status': 'Pending',
          'transactionId': '',
          'createdAt': FieldValue.serverTimestamp(),
          'dueDate': Timestamp.fromDate(DateTime(now.year, now.month, 30)),
          'monthKey': currentMonthKey,
        });
      }

      await batch.commit();

      if (mounted) {
        _commonAmountController.clear();
        _commonReasonController.clear();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Success: ₹${splitAmount.toStringAsFixed(2)} billed to $familyCount flats.", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Database Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isGeneratingCommonBill = false);
    }
  }

  // --- LOGIC: VERIFY PAYMENTS ---
  void _verifyPayment(String docId) async {
    await FirebaseFirestore.instance.collection('bills').doc(docId).update({
      'status': 'Paid',
      'verifiedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payment Verified", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 800;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: const IconThemeData(color: AppTheme.primary),
          title: Text(
            "Financial Ledger",
            style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          bottom: const TabBar(
            isScrollable: true,
            indicatorColor: AppTheme.primary,
            labelColor: AppTheme.primary,
            unselectedLabelColor: AppTheme.textMuted,
            indicatorWeight: 3,
            tabs: [
              Tab(text: "Global Settings"),
              Tab(text: "Issue Bills"),
              Tab(text: "Verify UTRs")
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: GLOBAL SETTINGS & QR UPLOAD
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20.0),
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
                        const Text("Master Configuration", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        const Text("Set the standard monthly maintenance. The system automatically generates bills for all residents based on this value.", style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.5)),
                        const SizedBox(height: 25),

                        _buildPremiumInput(controller: _globalMaintController, label: "Global Maintenance Fee (₹)", icon: Icons.payments, isNumber: true),

                        const SizedBox(height: 30),
                        const Text("Society Bank Account QR", style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 15),

                        // Styled QR Image Preview
                        Center(
                          child: InkWell(
                            onTap: _pickImage,
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              height: 220, width: 220,
                              decoration: BoxDecoration(
                                color: AppTheme.background,
                                border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 2),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [AppTheme.glowEffect],
                              ),
                              child: _qrCodeBase64 != null && _qrCodeBase64!.isNotEmpty
                                  ? ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(base64Decode(_qrCodeBase64!), fit: BoxFit.cover),
                              )
                                  : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner, size: 60, color: AppTheme.primary),
                                  SizedBox(height: 10),
                                  Text("Tap to Upload QR", style: TextStyle(color: AppTheme.textMuted, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 40),
                        _buildPremiumButton(
                            label: "Save Configuration",
                            isLoading: _isSavingSettings,
                            onPressed: _saveGlobalMaintenance
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // TAB 2: ISSUE CUSTOM & COMMON BILLS
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: isWideScreen
                      ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildCustomInvoiceSection()),
                      const SizedBox(width: 20),
                      Expanded(child: _buildCommonBillSection()),
                    ],
                  )
                      : Column(
                    children: [
                      _buildCustomInvoiceSection(),
                      const SizedBox(height: 20),
                      _buildCommonBillSection(),
                    ],
                  ),
                ),
              ),
            ),

            // TAB 3: VERIFY PAYMENTS - REBUILT TO FIX LISTTILE OVERFLOW
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('bills')
                      .where('org_id', isEqualTo: widget.orgId)
                      .where('status', isEqualTo: 'Under Review').snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text("No payments pending verification.", style: TextStyle(color: AppTheme.textMuted)));

                    final docs = snapshot.data!.docs;

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data() as Map<String, dynamic>;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppTheme.cardBg,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.borderHalf),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // LEFT COLUMN: Allows heading to expand naturally without competing for space
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "${data['type']} - Flat ${data['flatTarget']}",
                                      style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        "UTR: ${data['transactionId']}",
                                        style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted, fontSize: 14)
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),

                              // RIGHT COLUMN: Amount & Button stacked vertically
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "₹${data['baseAmount']}",
                                    style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 18),
                                  ),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.success.withOpacity(0.2),
                                      foregroundColor: AppTheme.success,
                                      elevation: 0,
                                      minimumSize: Size.zero, // Prevents default excessive padding from breaking height
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: AppTheme.success)),
                                    ),
                                    onPressed: () => _verifyPayment(docs[index].id),
                                    child: const Text("Verify", style: TextStyle(fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  // --- TAB 2 UI COMPONENTS EXCTRACTED FOR RESPONSIVENESS ---

  Widget _buildCustomInvoiceSection() {
    bool showReasonField = _invoiceType == 'Penalty' || _invoiceType == 'Other';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Generate Custom Invoice", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),

          // PREMIUM AUTOCOMPLETE FOR TARGET FLAT
          Autocomplete<String>(
            optionsBuilder: (TextEditingValue textValue) {
              if (textValue.text == '') return const Iterable<String>.empty();
              return _allFlats.where((String option) => option.toUpperCase().contains(textValue.text.toUpperCase()));
            },
            onSelected: (String selection) {
              _flatTargetController.text = selection;
              FocusScope.of(context).unfocus();
            },
            fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
              if (controller.text != _flatTargetController.text && _flatTargetController.text.isNotEmpty) {
                controller.text = _flatTargetController.text;
              }
              return TextField(
                controller: controller,
                focusNode: focusNode,
                style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 16),
                decoration: InputDecoration(
                  labelText: "Target Flat (e.g. A-101)",
                  labelStyle: const TextStyle(color: AppTheme.textMuted),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 20),
                  filled: true,
                  fillColor: AppTheme.background,
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                ),
                onChanged: (val) => _flatTargetController.text = val,
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: MediaQuery.of(context).size.width > 800 ? 350 : MediaQuery.of(context).size.width - 80, // Adapt dropdown width
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.cardBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.borderHalf),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
                    ),
                    child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        separatorBuilder: (c, i) => const Divider(color: AppTheme.borderHalf, height: 1),
                        itemBuilder: (context, index) {
                          final option = options.elementAt(index);
                          return ListTile(
                            title: Text(option, style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                            onTap: () => onSelected(option),
                          );
                        }
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 15),

          // Conditional Dropdown
          DropdownButtonFormField<String>(
            value: _invoiceType,
            dropdownColor: AppTheme.cardBg,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
            icon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
            decoration: InputDecoration(
              labelText: "Invoice Type", labelStyle: const TextStyle(color: AppTheme.textMuted),
              prefixIcon: const Icon(Icons.receipt_long, color: AppTheme.textMuted, size: 20),
              filled: true, fillColor: AppTheme.background,
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
            ),
            items: ['Light Bill', 'Penalty', 'Other'].map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (val) => setState(() {
              _invoiceType = val!;
              // Clear the reason if we switch away from Penalty/Other
              if (_invoiceType == 'Light Bill') _customReasonController.clear();
            }),
          ),
          const SizedBox(height: 15),

          // DYNAMIC REASON FIELD (Expands for Penalty OR Other)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: showReasonField
                ? Padding(
              padding: const EdgeInsets.only(bottom: 15.0),
              child: _buildPremiumInput(
                  controller: _customReasonController,
                  label: _invoiceType == 'Penalty' ? "Reason for Penalty" : "Specify Invoice Details",
                  icon: _invoiceType == 'Penalty' ? Icons.warning_amber : Icons.edit_note
              ),
            )
                : const SizedBox.shrink(),
          ),

          _buildPremiumInput(controller: _invoiceAmountController, label: "Amount (₹)", icon: Icons.currency_rupee, isNumber: true),
          const SizedBox(height: 20),

          _buildPremiumButton(
            label: "Issue Invoice",
            isLoading: _isGeneratingInvoice,
            onPressed: _generateCustomInvoice,
          )
        ],
      ),
    );
  }

  Widget _buildCommonBillSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart, color: AppTheme.secondary, size: 24),
              const SizedBox(width: 10),
              const Expanded(child: Text("Common Bill Distributor", style: TextStyle(color: AppTheme.secondary, fontSize: 18, fontWeight: FontWeight.bold))),
            ],
          ),
          const SizedBox(height: 8),
          const Text("Enter the total society expense. The system will automatically divide this amount equally among all registered families.", style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4)),
          const SizedBox(height: 20),

          _buildPremiumInput(controller: _commonAmountController, label: "Total Expense Amount (₹)", icon: Icons.account_balance, isNumber: true),
          const SizedBox(height: 15),
          _buildPremiumInput(controller: _commonReasonController, label: "Expense Reason (e.g. Lift Repair)", icon: Icons.construction),
          const SizedBox(height: 20),

          InkWell(
            onTap: _isGeneratingCommonBill ? null : _generateCommonBill,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.secondary),
              ),
              child: Center(
                child: _isGeneratingCommonBill
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.secondary, strokeWidth: 2))
                    : const Text("Split & Distribute Bill", style: TextStyle(color: AppTheme.secondary, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          )
        ],
      ),
    );
  }

  // --- PREMIUM UI HELPERS ---

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
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

  Widget _buildPremiumButton({required String label, required bool isLoading, required VoidCallback onPressed}) {
    return InkWell(
      onTap: isLoading ? null : onPressed,
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
          child: isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
              : Text(label, style: const TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }
}