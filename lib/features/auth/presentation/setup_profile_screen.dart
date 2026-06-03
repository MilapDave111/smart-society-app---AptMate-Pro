import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; //
import 'package:flutter/material.dart';

class SetupProfileScreen extends StatefulWidget {
  const SetupProfileScreen({super.key});

  @override
  State<SetupProfileScreen> createState() => _SetupProfileScreenState();
}

class _SetupProfileScreenState extends State<SetupProfileScreen> {
  final _nameController = TextEditingController();
  String _selectedWing = 'A';
  final _flatController = TextEditingController();

  void _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      String? fcmToken = await FirebaseMessaging.instance.getToken();

      // SECURE CHECK: Find the document the ADMIN already added
      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phone', isEqualTo: user.phoneNumber?.replaceAll('+91', ''))
          .get();

      if (query.docs.isNotEmpty) {
        // Update the existing Admin-created record
        await query.docs.first.reference.update({
          'uid': user.uid,
          'fcmToken': fcmToken,
          'name': _nameController.text.trim(),
          'wing': _selectedWing,
          'flatNumber': _flatController.text.trim(),
        });
      } else {
        // Brute honesty SnackBar
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Access Denied: You are not pre-registered by the Secretary.")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Complete Your Profile")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Full Name")),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedWing,
              items: ['A', 'B', 'C', 'D']
                  .map((w) => DropdownMenuItem(value: w, child: Text("Wing $w")))
                  .toList(),
              onChanged: (val) => setState(() => _selectedWing = val!),
              decoration: const InputDecoration(labelText: "Select Wing"),
            ),
            TextField(
              controller: _flatController,
              decoration: const InputDecoration(labelText: "Flat Number"),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _saveProfile,
              child: const Text("Save and Enter Society"),
            ),
          ],
        ),
      ),
    );
  }
}