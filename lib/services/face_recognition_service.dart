import 'dart:math';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class FaceRecognitionService {
  Interpreter? _interpreter;

  // 1. Boot up the Neural Network into the phone's RAM
  Future<void> initialize() async {
    try {
      _interpreter = await Interpreter.fromAsset('assets/models/mobilefacenet.tflite');
    } catch (e) {
      throw Exception("CRITICAL FAILURE: Neural Network model failed to load. Check your assets folder. Error: $e");
    }
  }

  // 2. Convert the raw photo pixels into a 192-dimensional math vector
  List<double> generateEmbedding(img.Image faceImage) {
    if (_interpreter == null) throw Exception("Interpreter not loaded. Call initialize() first.");

    // MobileFaceNet strictly requires a 112x112 pixel square.
    img.Image resizedImage = img.copyResize(faceImage, width: 112, height: 112);

    // Create an empty 4D Tensor array matching the exact shape MobileFaceNet expects: [1, 112, 112, 3]
    var input = List.generate(1, (i) => List.generate(112, (j) => List.generate(112, (k) => List.generate(3, (l) => 0.0))));

    // Loop through every single pixel and normalize the RGB values to float numbers between -1.0 and 1.0
    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        var pixel = resizedImage.getPixel(x, y);
        input[0][y][x][0] = (pixel.r - 127.5) / 127.5; // Red
        input[0][y][x][1] = (pixel.g - 127.5) / 127.5; // Green
        input[0][y][x][2] = (pixel.b - 127.5) / 127.5; // Blue
      }
    }

    // Create an empty array to catch the neural network's output: [1, 192]
    var output = List.generate(1, (i) => List.filled(192, 0.0));

    // Execute the mathematical inference
    _interpreter!.run(input, output);

    // Return the 192 decimal numbers that uniquely identify this face
    return output[0];
  }

  // 3. Calculate Euclidean Distance between two face vectors
  double calculateDistance(List<double> embedding1, List<double> embedding2) {
    if (embedding1.length != embedding2.length) return 999.0; // Math failure, arrays don't match

    double sum = 0.0;
    for (int i = 0; i < embedding1.length; i++) {
      sum += pow((embedding1[i] - embedding2[i]), 2);
    }
    return sqrt(sum);
  }

  // 4. The Security Gatekeeper (Threshold determines strictness. 1.0 is standard for MobileFaceNet)
  bool isMatch(List<double> registeredFace, List<double> liveFace, {double threshold = 1.0}) {
    double distance = calculateDistance(registeredFace, liveFace);
    return distance < threshold;
  }
}