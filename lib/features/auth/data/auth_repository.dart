import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// This 'Provider' allows the rest of the app to access Firebase Auth easily
final authRepositoryProvider = Provider((ref) => AuthRepository(FirebaseAuth.instance));

// This 'StreamProvider' listens to whether a user is logged in or out in real-time
final authStateProvider = StreamProvider((ref) {
  return ref.read(authRepositoryProvider).authStateChanges;
});

class AuthRepository {
  final FirebaseAuth _auth;
  AuthRepository(this._auth);

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Logic for sending OTP
  Future<void> verifyPhone(String phoneNumber, Function(String, int?) onCodeSent) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (e) => throw e,
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (id) {},
    );
  }
}