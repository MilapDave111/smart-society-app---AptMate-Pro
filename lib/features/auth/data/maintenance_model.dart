import 'package:cloud_firestore/cloud_firestore.dart';

class MaintenanceModel {
  final String month;
  final double amount;
  final bool isPaid;
  final DateTime dueDate;

  MaintenanceModel({
    required this.month,
    required this.amount,
    required this.isPaid,
    required this.dueDate,
  });

  factory MaintenanceModel.fromFirestore(Map<String, dynamic> data) {
    return MaintenanceModel(
      month: data['month'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
      isPaid: data['isPaid'] ?? false,
      dueDate: (data['dueDate'] as Timestamp).toDate(),
    );
  }
}