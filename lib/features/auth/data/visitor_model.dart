import 'package:cloud_firestore/cloud_firestore.dart';

class VisitorModel {
  final String name;
  final String purpose; // e.g., "Delivery", "Guest"
  final String flatTarget;
  final DateTime entryTime;
  final String status; // "Inside" or "Left"

  VisitorModel({
    required this.name,
    required this.purpose,
    required this.flatTarget,
    required this.entryTime,
    this.status = "Inside",
  });

  factory VisitorModel.fromFirestore(Map<String, dynamic> data) {
    return VisitorModel(
      name: data['name'] ?? '',
      purpose: data['purpose'] ?? '',
      flatTarget: data['flatTarget'] ?? '',
      entryTime: (data['entryTime'] as Timestamp).toDate(),
      status: data['status'] ?? 'Inside',
    );
  }
}