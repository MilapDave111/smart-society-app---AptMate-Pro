import 'package:cloud_firestore/cloud_firestore.dart';

class NoticeModel {
  final String title;
  final String content;
  final DateTime timestamp;

  NoticeModel({required this.title, required this.content, required this.timestamp});

  // Convert Firestore data into this Model
  factory NoticeModel.fromFirestore(Map<String, dynamic> data) {
    return NoticeModel(
      title: data['title'] ?? '',
      content: data['content'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
    );
  }
}