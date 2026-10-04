import 'package:firebase_auth/firebase_auth.dart';

class NewsAccount {
  const NewsAccount({required this.id, required this.email});
  final String id;
  final String email;
}

abstract interface class AuthClient {
  Stream<NewsAccount?> get accounts;
  Future<void> signIn(String email, String password);
  Future<void> signUp(String email, String password);
  Future<void> resetPassword(String email);
  Future<void> signOut();
}

class FirebaseAuthClient implements AuthClient {
  FirebaseAuth get _auth => FirebaseAuth.instance;
  @override
  Stream<NewsAccount?> get accounts => _auth.authStateChanges().map(
    (user) => user == null
        ? null
        : NewsAccount(id: user.uid, email: user.email ?? ''),
  );
  @override
  Future<void> signIn(String email, String password) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signUp(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  @override
  Future<void> resetPassword(String email) =>
      _auth.sendPasswordResetEmail(email: email);
  @override
  Future<void> signOut() => _auth.signOut();
}

String authErrorMessage(Object error) {
  if (error is! FirebaseAuthException) {
    return 'Unable to connect. Please try again.';
  }
  return switch (error.code) {
    'invalid-email' => 'Enter a valid email address.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is incorrect.',
    'email-already-in-use' =>
      'This email already has an account. Sign in instead.',
    'weak-password' => 'Choose a stronger password with at least 8 characters.',
    'network-request-failed' => 'Check your internet connection and try again.',
    'too-many-requests' =>
      'Too many attempts. Please wait before trying again.',
    'user-disabled' => 'This account has been disabled.',
    'operation-not-allowed' =>
      'Email sign-in is currently unavailable. Please try again later.',
    _ => 'Unable to complete the request. Please try again.',
  };
}
