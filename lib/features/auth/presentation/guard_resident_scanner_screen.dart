import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import '../../../theme/app_theme.dart';
import '../../../services/face_recognition_service.dart';

class GuardResidentScannerScreen extends StatefulWidget {
  final String orgId;
  const GuardResidentScannerScreen({super.key, required this.orgId});

  @override
  State<GuardResidentScannerScreen> createState() => _GuardResidentScannerScreenState();
}

class _GuardResidentScannerScreenState extends State<GuardResidentScannerScreen> {
  final FaceRecognitionService _mlService = FaceRecognitionService();
  late final FaceDetector _faceDetector;

  bool _isBooting = true;
  bool _isScanning = false;
  List<Map<String, dynamic>> _registeredResidents = [];

  @override
  void initState() {
    super.initState();
    _prepareSystem();
  }

  Future<void> _prepareSystem() async {
    try {
      // 1. Load TensorFlow Model
      await _mlService.initialize();
      _faceDetector = FaceDetector(options: FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate));

      // 2. Pre-load Organization's Face Vectors into RAM for fast processing
      final snapshot = await FirebaseFirestore.instance.collection('family_members')
          .where('org_id', isEqualTo: widget.orgId) // STRICT ISOLATION
          .get();

      List<Map<String, dynamic>> residents = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['faceVector'] != null) {
          residents.add({
            'name': data['name'],
            'flat': data['flatTarget'],
            'vector': List<double>.from(data['faceVector']),
          });
        }
      }

      if (mounted) {
        setState(() {
          _registeredResidents = residents;
          _isBooting = false;
        });
      }
    } catch (e) {
      debugPrint("System Boot Error: $e");
      if (mounted) setState(() => _isBooting = false);
    }
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _performBiometricMatch() async {
    if (_registeredResidents.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No residents registered with biometrics.", style: TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.warning));
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);
    if (pickedFile == null) return;

    setState(() => _isScanning = true);

    try {
      final inputImage = InputImage.fromFilePath(pickedFile.path);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isEmpty) throw Exception("No face detected.");
      if (faces.length > 1) throw Exception("Multiple faces detected. Please scan one person.");

      final bytes = await File(pickedFile.path).readAsBytes();
      img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null) throw Exception("Failed to decode image.");

      final rect = faces.first.boundingBox;
      int x = rect.left.toInt().clamp(0, originalImage.width);
      int y = rect.top.toInt().clamp(0, originalImage.height);
      int w = rect.width.toInt().clamp(0, originalImage.width - x);
      int h = rect.height.toInt().clamp(0, originalImage.height - y);

      img.Image croppedFace = img.copyCrop(originalImage, x: x, y: y, width: w, height: h);

      // Generate vector from the live photo
      List<double> liveVector = _mlService.generateEmbedding(croppedFace);

      // Match against the pre-loaded vectors
      double bestDistance = double.infinity;
      Map<String, dynamic>? bestMatch;

      for (var resident in _registeredResidents) {
        double distance = _mlService.calculateDistance(liveVector, resident['vector']);
        if (distance < bestDistance) {
          bestDistance = distance;
          bestMatch = resident;
        }
      }

      // THRESHOLD SETTING (Adjust if too strict/loose)
      if (bestDistance < 1.0 && bestMatch != null) {
        _showResultDialog(true, bestMatch['name'], bestMatch['flat']);
      } else {
        _showResultDialog(false, "Unknown Person", "Access Denied");
      }

    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceAll("Exception: ", ""), style: const TextStyle(color: AppTheme.background)), backgroundColor: AppTheme.error));
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _showResultDialog(bool isMatch, String name, String flat) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: isMatch ? AppTheme.success : AppTheme.error, width: 2)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isMatch ? Icons.verified_user : Icons.gpp_bad, size: 80, color: isMatch ? AppTheme.success : AppTheme.error),
            const SizedBox(height: 20),
            Text(isMatch ? "VERIFIED RESIDENT" : "UNAUTHORIZED", style: TextStyle(color: isMatch ? AppTheme.success : AppTheme.error, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.bold)),
            Text(flat, style: GoogleFonts.jetBrainsMono(color: AppTheme.primary, fontSize: 16)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE", style: TextStyle(color: AppTheme.textMuted)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isBooting) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: AppTheme.primary),
              const SizedBox(height: 20),
              Text("Booting AI Engine & Loading Secure Vectors...", style: GoogleFonts.jetBrainsMono(color: AppTheme.primary)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: AppTheme.primary),
        title: Text("Resident AI Scan", style: GoogleFonts.playfairDisplay(color: AppTheme.primary, fontSize: 24, fontWeight: FontWeight.bold)),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppTheme.primary.withOpacity(0.2), width: 2)),
              child: const Icon(Icons.face_unlock_outlined, size: 100, color: AppTheme.primary),
            ),
            const SizedBox(height: 40),
            Text("Point camera at Resident", style: GoogleFonts.jetBrainsMono(color: AppTheme.textMuted)),
            const SizedBox(height: 20),

            InkWell(
              onTap: _isScanning ? null : _performBiometricMatch,
              child: Container(
                width: 200, padding: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(gradient: AppTheme.goldGradient, borderRadius: BorderRadius.circular(30)),
                child: Center(
                  child: _isScanning
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: AppTheme.background, strokeWidth: 2))
                      : const Text("SCAN FACE", style: TextStyle(color: AppTheme.background, fontWeight: FontWeight.bold)),
                ),
              ),
            ),
            const SizedBox(height: 15),
            Text("${_registeredResidents.length} Residents in RAM Memory", style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}