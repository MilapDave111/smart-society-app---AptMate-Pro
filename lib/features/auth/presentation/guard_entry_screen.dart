import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../../../theme/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class GuardEntryScreen extends StatefulWidget {
  final String orgId;
  const GuardEntryScreen({super.key, required this.orgId});

  @override
  State<GuardEntryScreen> createState() => _GuardEntryScreenState();
}

class _GuardEntryScreenState extends State<GuardEntryScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  String _flatTargetInput = '';
  String _purposeInput = '';
  bool _isLoading = false;

  Map<String, String> _flatData = {};
  final List<String> _purposeOptions = ['Delivery (Amazon/Flipkart)', 'Guest / Relative', 'Maintenance / Plumber', 'Cab / Taxi', 'Maid / Helper', 'Property Agent'];

  File? _imageFile;
  bool _isProcessingImage = false;
  bool _faceDetected = false;
  late final FaceDetector _faceDetector;

  @override
  void initState() {
    super.initState();
    _fetchFlats();
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
        enableTracking: false,
      ),
    );
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _fetchFlats() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('users')
          .where('org_id', isEqualTo: widget.orgId) // SCOPED
          .where('role', isEqualTo: 'resident').get();
      Map<String, String> flats = {};
      for (var doc in snapshot.docs) {
        String flat = "${doc['wing']}-${doc['flatNumber']}".toUpperCase();
        flats[flat] = doc['status'] ?? 'Left';
      }
      if (mounted) setState(() => _flatData = flats);
    } catch (e) {
      debugPrint("Error fetching flats: $e");
    }
  }

  Future<void> _captureAndAnalyzePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 50, maxWidth: 400);

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _isProcessingImage = true;
      _faceDetected = false;
    });

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      setState(() {
        _faceDetected = faces.isNotEmpty;
        _isProcessingImage = false;
      });

      if (!_faceDetected && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("REJECTED: No human face detected.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
      }
    } catch (e) {
      setState(() => _isProcessingImage = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Camera Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    }
  }

  void _logEntry() async {
    final flatTarget = _flatTargetInput.trim().toUpperCase();
    final purpose = _purposeInput.trim();

    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || flatTarget.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fill all mandatory fields", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }
    if (_phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Phone number must be exactly 10 digits", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    if (!_faceDetected || _imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("A valid face scan is mandatory to log entry.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
      return;
    }

    setState(() => _isLoading = true);

    try {
      final bytes = await _imageFile!.readAsBytes();
      final String base64Image = base64Encode(bytes);

      if (base64Image.length > 900000) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image too large. Retake.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
        setState(() => _isLoading = false);
        return;
      }

      // 1. CREATE THE PENDING TICKET WITH ORG_ID
      DocumentReference docRef = await FirebaseFirestore.instance.collection('visitors').add({
        'org_id': widget.orgId,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'flatTarget': flatTarget,
        'purpose': purpose.isEmpty ? 'General Visit' : purpose,
        'status': 'Pending',
        'entryTime': FieldValue.serverTimestamp(),
        'exitTime': null,
        'photoBase64': base64Image,
      });

      // 2. FETCH THE RESIDENT'S FCM TOKEN
      final parts = flatTarget.split('-');
      if (parts.length == 2) {
        final residentSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('org_id', isEqualTo: widget.orgId)
            .where('wing', isEqualTo: parts[0])
            .where('flatNumber', isEqualTo: parts[1])
            .limit(1)
            .get();

        if (residentSnap.docs.isNotEmpty) {
          final residentData = residentSnap.docs.first.data();
          final String? targetToken = residentData['fcmToken'];

          // 3. PING SERVER
          if (targetToken != null) {
            final url = Uri.parse('https://aptmate-backend-server.onrender.com/send-gate-alert');
            await http.post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'token': targetToken,
                'title': 'GATE APPROVAL REQUIRED',
                'body': '${_nameController.text.trim()} is at the gate for ${purpose.isEmpty ? 'General Visit' : purpose}.',
                'visitorId': docRef.id
              }),
            );
          }
        }
      }

      // 4. CLEAR THE FORM
      if (mounted) {
        _nameController.clear();
        _phoneController.clear();
        setState(() {
          _flatTargetInput = '';
          _purposeInput = '';
          _imageFile = null;
          _faceDetected = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Sent to Flat $flatTarget for Approval. Process next visitor.", style: const TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
              backgroundColor: AppTheme.warning,
              duration: const Duration(seconds: 3),
            )
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Database Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text("Gate Entry Protocol", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _imageFile != null ? (_faceDetected ? AppTheme.success : AppTheme.error) : AppTheme.borderHalf, width: 2)),
              child: Column(
                children: [
                  const Text("Biometric Scan", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  if (_imageFile != null)
                    Container(
                      height: 120, width: 120,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _faceDetected ? AppTheme.success : AppTheme.error, width: 4), image: DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)),
                    )
                  else
                    Container(
                      height: 100, width: 100,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(color: AppTheme.background, shape: BoxShape.circle, border: Border.all(color: AppTheme.borderHalf)),
                      child: const Icon(Icons.camera_front, color: AppTheme.textMuted, size: 40),
                    ),

                  InkWell(
                    onTap: _isProcessingImage ? null : _captureAndAnalyzePhoto,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                      decoration: BoxDecoration(color: AppTheme.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary)),
                      child: _isProcessingImage
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                          : Text(_imageFile == null ? "Capture Face" : "Retake", style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: AppTheme.cardGradient, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.borderHalf)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Visitor Details", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),

                  _buildPremiumInput(controller: _nameController, label: "Full Name", icon: Icons.person),
                  const SizedBox(height: 15),
                  _buildPremiumInput(controller: _phoneController, label: "Phone Number", icon: Icons.phone, isPhone: true),
                  const SizedBox(height: 15),

                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textValue) {
                      if (textValue.text.isEmpty) return const Iterable<String>.empty();
                      return _flatData.keys.where((String option) => option.contains(textValue.text.toUpperCase()));
                    },
                    onSelected: (String selection) {
                      setState(() => _flatTargetInput = selection.toUpperCase());
                      FocusScope.of(context).unfocus();
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      if (_flatTargetInput.isEmpty && controller.text.isNotEmpty) controller.clear();
                      return TextField(
                        controller: controller, focusNode: focusNode, style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: "Target Flat (e.g. A-101)", labelStyle: const TextStyle(color: AppTheme.textMuted),
                          prefixIcon: const Icon(Icons.meeting_room, color: AppTheme.textMuted, size: 20),
                          filled: true, fillColor: AppTheme.background,
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                        ),
                        onChanged: (val) => setState(() => _flatTargetInput = val.toUpperCase()),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: MediaQuery.of(context).size.width - 80, margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                            child: ListView.separated(
                                padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length,
                                separatorBuilder: (c, i) => const Divider(color: AppTheme.borderHalf, height: 1),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(title: Text(option, style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontWeight: FontWeight.bold)), onTap: () => onSelected(option));
                                }
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  if (_flatTargetInput.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                      child: _buildResidentStatusBadge(_flatTargetInput),
                    ),

                  const SizedBox(height: 7),

                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textValue) {
                      if (textValue.text.isEmpty) return _purposeOptions;
                      return _purposeOptions.where((String option) => option.toLowerCase().contains(textValue.text.toLowerCase()));
                    },
                    onSelected: (String selection) {
                      _purposeInput = selection;
                      FocusScope.of(context).unfocus();
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      if (_purposeInput.isEmpty && controller.text.isNotEmpty) controller.clear();
                      return TextField(
                        controller: controller, focusNode: focusNode, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
                        decoration: InputDecoration(
                          labelText: "Purpose of Visit", labelStyle: const TextStyle(color: AppTheme.textMuted),
                          prefixIcon: const Icon(Icons.badge, color: AppTheme.textMuted, size: 20),
                          suffixIcon: const Icon(Icons.arrow_drop_down, color: AppTheme.primary),
                          filled: true, fillColor: AppTheme.background,
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
                        ),
                        onChanged: (val) => _purposeInput = val,
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: MediaQuery.of(context).size.width - 80, margin: const EdgeInsets.only(top: 8),
                            decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                            child: ListView.separated(
                                padding: EdgeInsets.zero, shrinkWrap: true, itemCount: options.length,
                                separatorBuilder: (c, i) => const Divider(color: AppTheme.borderHalf, height: 1),
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(title: Text(option, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)), onTap: () => onSelected(option));
                                }
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 25),

                  InkWell(
                    onTap: _isLoading ? null : _logEntry,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(gradient: AppTheme.goldGradient, borderRadius: BorderRadius.circular(12), boxShadow: const [AppTheme.glowEffect]),
                      child: Center(
                        child: _isLoading
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                            : const Text("Log Entry & Secure Data", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  )
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResidentStatusBadge(String flatTarget) {
    if (!_flatData.containsKey(flatTarget)) return const SizedBox.shrink();
    String status = _flatData[flatTarget]!;
    bool isInside = status == 'Inside';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: isInside ? AppTheme.success.withOpacity(0.1) : AppTheme.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8), border: Border.all(color: isInside ? AppTheme.success : AppTheme.error),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isInside ? Icons.home : Icons.lock, color: isInside ? AppTheme.success : AppTheme.error, size: 16),
          const SizedBox(width: 8),
          Text(isInside ? "Resident is At Home" : "Flat is Locked / Away", style: TextStyle(color: isInside ? AppTheme.success : AppTheme.error, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false,bool isPhone = false}) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : (isNumber ? TextInputType.number : TextInputType.text),
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