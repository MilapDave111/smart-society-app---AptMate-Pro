import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../../../theme/app_theme.dart';
import '../../../services/face_recognition_service.dart';
import 'package:flutter/services.dart';

class FamilyDetailScreen extends StatefulWidget {
  final String flatId;
  final String primaryName;
  final String orgId; // INJECTED ORG_ID
  const FamilyDetailScreen({super.key, required this.flatId, required this.primaryName, required this.orgId});

  @override
  State<FamilyDetailScreen> createState() => _FamilyDetailScreenState();
}

class _FamilyDetailScreenState extends State<FamilyDetailScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isSaving = false;
  bool _showAddForm = false; // Toggles between Directory List and ML Registration Form

  // ML Pipeline Variables
  File? _imageFile;
  List<double>? _faceVector;
  bool _isProcessingImage = false;
  late final FaceDetector _faceDetector;
  final FaceRecognitionService _mlService = FaceRecognitionService();
  bool _engineReady = false;

  @override
  void initState() {
    super.initState();
    _initializeMLEngine();
  }

  Future<void> _initializeMLEngine() async {
    try {
      await _mlService.initialize();
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: false,
          enableContours: false,
          enableTracking: false,
        ),
      );
      if (mounted) setState(() => _engineReady = true);
    } catch (e) {
      debugPrint("Engine Boot Failure: $e");
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _captureAndExtractVector() async {
    if (!_engineReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("AI Engine is still booting. Please wait.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile == null) return;

    setState(() {
      _imageFile = File(pickedFile.path);
      _isProcessingImage = true;
      _faceVector = null;
    });

    try {
      // 1. Detect the physical location of the face in the photo
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final List<Face> faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) throw Exception("No face detected. Retake photo.");
      if (faces.length > 1) throw Exception("Multiple faces detected. Frame only one person.");

      // 2. Decode the raw bytes into a pixel map
      final bytes = await _imageFile!.readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception("Failed to decode image pixels.");

      // 3. Mathematically crop the face out of the background noise
      final rect = faces.first.boundingBox;
      int x = rect.left.toInt().clamp(0, originalImage.width);
      int y = rect.top.toInt().clamp(0, originalImage.height);
      int w = rect.width.toInt().clamp(0, originalImage.width - x);
      int h = rect.height.toInt().clamp(0, originalImage.height - y);

      img.Image croppedFace = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);

      // 4. Feed the clean, cropped face to TensorFlow to generate the math vector
      List<double> vector = _mlService.generateEmbedding(croppedFace);

      setState(() {
        _faceVector = vector;
        _isProcessingImage = false;
      });

    } catch (e) {
      setState(() {
        _imageFile = null;
        _faceVector = null;
        _isProcessingImage = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""), style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    }
  }

  void _addMember() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Member name is required", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }
    if (_phoneController.text.isNotEmpty && _phoneController.text.length != 10) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("If provided, phone number must be exactly 10 digits", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    if (_faceVector == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Facial registration scan is strictly required.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance.collection('family_members').add({
        'org_id': widget.orgId, // ORG ID BOUND TO VECTOR
        'flatTarget': widget.flatId,
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
        'faceVector': _faceVector,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        _nameController.clear();
        _phoneController.clear();
        setState(() {
          _imageFile = null;
          _faceVector = null;
          _showAddForm = false; // Drop user back to list upon successful save
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Member Added & Vector Encoded", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.success));
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Database Error: $e", style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _removeMember(String docId) async {
    await FirebaseFirestore.instance.collection('family_members').doc(docId).delete();
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
          return false;
        }
        return true;
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
              _showAddForm ? "Register Member" : "Flat ${widget.flatId}",
              style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)
          ),
          actions: [
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
                        Icon(Icons.person_add, color: AppTheme.primary, size: 18),
                        SizedBox(width: 8),
                        Text("Add Member", style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: _showAddForm ? _buildFormView() : _buildListView(),
          ),
        ),
      ),
    );
  }

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
            const Text("Register New Member", style: TextStyle(color: AppTheme.primary, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            Center(
              child: InkWell(
                onTap: _isProcessingImage ? null : _captureAndExtractVector,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _faceVector != null ? AppTheme.success : AppTheme.primary)
                  ),
                  child: Column(
                    children: [
                      if (_imageFile != null)
                        Container(
                          height: 80, width: 80, margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: _faceVector != null ? AppTheme.success : AppTheme.error, width: 3),
                              image: DecorationImage(image: FileImage(_imageFile!), fit: BoxFit.cover)
                          ),
                        )
                      else
                        const Icon(Icons.face_retouching_natural, color: AppTheme.primary, size: 40),

                      const SizedBox(height: 8),
                      _isProcessingImage
                          ? const SizedBox(height: 15, width: 15, child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2))
                          : Text(
                          _faceVector != null ? "Vector Encoded" : "Tap to Scan Face",
                          style: TextStyle(color: _faceVector != null ? AppTheme.success : AppTheme.primary, fontWeight: FontWeight.bold, fontSize: 12)
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
            _buildPremiumInput(controller: _nameController, label: "Full Name", icon: Icons.person),
            const SizedBox(height: 15),
            _buildPremiumInput(controller: _phoneController, label: "Phone (Optional)", icon: Icons.phone, isPhone: true),
            const SizedBox(height: 20),

            InkWell(
              onTap: _isSaving ? null : _addMember,
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
                      : const Text("Register & Save Vector", style: TextStyle(color: AppTheme.background, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Text("Registered Members of ${widget.flatId}", style: const TextStyle(color: AppTheme.textMuted, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('family_members')
                .where('org_id', isEqualTo: widget.orgId) // SCOPED
                .where('flatTarget', isEqualTo: widget.flatId)
                .orderBy('createdAt').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text("Database Error:\n${snapshot.error}", style: const TextStyle(color: AppTheme.error)));
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppTheme.primary));

              final docs = snapshot.data?.docs ?? [];

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                itemCount: docs.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 15),
                      decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.primary.withOpacity(0.5))),
                      child: ListTile(
                        leading: const Icon(Icons.star, color: AppTheme.primary),
                        title: Text(widget.primaryName, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                        subtitle: const Text("Primary Account Holder", style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                      ),
                    );
                  }

                  final data = docs[index - 1].data() as Map<String, dynamic>;
                  final bool hasVector = data['faceVector'] != null;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(color: AppTheme.cardBg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.borderHalf)),
                    child: ListTile(
                      leading: Icon(hasVector ? Icons.memory : Icons.person_outline, color: hasVector ? AppTheme.success : AppTheme.textMuted),
                      title: Text(data['name'] ?? 'Unknown', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text(hasVector ? "Vector Registered" : "No Biometrics", style: TextStyle(color: hasVector ? AppTheme.success : AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                      trailing: IconButton(icon: const Icon(Icons.remove_circle_outline, color: AppTheme.error), onPressed: () => _removeMember(docs[index - 1].id)),
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

  Widget _buildPremiumInput({required TextEditingController controller, required String label, required IconData icon, bool isNumber = false,bool isPhone = false}) {
    return TextField(
      controller: controller,
      keyboardType: isPhone ? TextInputType.phone : (isNumber ? TextInputType.number : TextInputType.text),
      inputFormatters: isPhone
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)]
          : (isNumber ? [FilteringTextInputFormatter.digitsOnly] : null),
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label, labelStyle: const TextStyle(color: AppTheme.textMuted),
        prefixIcon: Icon(icon, color: AppTheme.textMuted, size: 20),
        filled: true, fillColor: AppTheme.background,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppTheme.primary, width: 1.5)),
      ),
    );
  }
}