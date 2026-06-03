import 'package:cloud_firestore/cloud_firestore.dart';

class ComplaintModel {
  final String title;
  final String description;
  final String category; // Plumbing, Electrical, Security, etc.
  final String status; // Pending, In-Progress, Resolved
  final DateTime createdAt;
  final String flatTarget;

  ComplaintModel({
    required this.title,
    required this.description,
    required this.category,
    this.status = 'Pending',
    required this.createdAt,
    required this.flatTarget,
  });

  factory ComplaintModel.fromFirestore(Map<String, dynamic> data) {
    return ComplaintModel(
      title: data['title'] ?? '',
      description: data['description'] ?? '',
      category: data['category'] ?? 'General',
      status: data['status'] ?? 'Pending',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      flatTarget: data['flatTarget'] ?? '',
    );
  }
}