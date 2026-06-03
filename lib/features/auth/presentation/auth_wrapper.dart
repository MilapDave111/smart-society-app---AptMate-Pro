import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/auth_repository.dart';
import 'login_screen.dart';
import 'dashboard_screen.dart';
import '../../../theme/app_theme.dart';

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user == null) return const LoginScreen();

        // Check if the user exists in the system via email or phone
        // The admin pre-registers them, so their doc MUST exist.
        return FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('users')
              .where('email', isEqualTo: user.email)
              .limit(1)
              .get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(backgroundColor: AppTheme.background, body: Center(child: CircularProgressIndicator(color: AppTheme.primary)));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              // Unauthorized / Not created by Admin
              FirebaseAuth.instance.signOut();
              return const LoginScreen();
            }

            // If found, update their UID if it's missing (syncing Auth with Firestore record)
            final doc = snapshot.data!.docs.first;
            if (doc['uid'] == null || doc['uid'] != user.uid) {
              doc.reference.update({'uid': user.uid});
            }

            // Direct entry to Dashboard (Profile Setup completely bypassed)
            return const DashboardScreen();
          },
        );
      },
      loading: () => const Scaffold(backgroundColor: AppTheme.background, body: Center(child: CircularProgressIndicator(color: AppTheme.primary))),
      error: (e, trace) => Scaffold(backgroundColor: AppTheme.background, body: Center(child: Text("Error: $e", style: const TextStyle(color: AppTheme.error)))),
    );
  }
}