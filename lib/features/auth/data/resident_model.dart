class ResidentModel {
  final String uid;
  final String name;
  final String wing;
  final String flatNumber;
  final String role; // 'resident', 'admin', or 'security'

  ResidentModel({
    required this.uid,
    required this.name,
    required this.wing,
    required this.flatNumber,
    this.role = 'resident',
  });

  // Convert to Map to send to Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'wing': wing,
      'flatNumber': flatNumber,
      'role': role,
    };
  }
}