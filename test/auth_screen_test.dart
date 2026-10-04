import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:globe_news_beta/auth/auth_client.dart';
import 'package:globe_news_beta/auth/auth_screen.dart';

class TestAuth implements AuthClient {
  final calls = <String>[];
  Object? failure;
  @override
  Stream<NewsAccount?> get accounts => Stream.value(null);
  @override
  Future<void> signIn(String email, String password) async {
    calls.add('in:$email');
    if (failure != null) throw failure!;
  }

  @override
  Future<void> signUp(String email, String password) async {
    calls.add('up:$email');
  }

  @override
  Future<void> resetPassword(String email) async {
    calls.add('reset:$email');
  }

  @override
  Future<void> signOut() async {}
}

void main() {
  Future<void> show(WidgetTester tester, TestAuth auth) async {
    await tester.pumpWidget(MaterialApp(home: AuthScreen(client: auth)));
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('invalid credentials are rejected before calling Firebase', (
    tester,
  ) async {
    final auth = TestAuth();
    await show(tester, auth);
    await submit(tester);
    expect(auth.calls, isEmpty);
    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });
  testWidgets('sign in trims email and displays a safe credential error', (
    tester,
  ) async {
    final auth = TestAuth()
      ..failure = FirebaseAuthException(code: 'invalid-credential');
    await show(tester, auth);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      ' reader@example.com ',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'test-password',
    );
    await submit(tester);
    expect(auth.calls, ['in:reader@example.com']);
    expect(find.text('The email or password is incorrect.'), findsOneWidget);
  });
  testWidgets('sign up requires matching passwords', (tester) async {
    final auth = TestAuth();
    await show(tester, auth);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'reader@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('auth-password')),
      'test-password',
    );
    await tester.enterText(find.byKey(const Key('auth-confirm')), 'different');
    await submit(tester);
    expect(auth.calls, isEmpty);
    await tester.enterText(
      find.byKey(const Key('auth-confirm')),
      'test-password',
    );
    await submit(tester);
    expect(auth.calls, ['up:reader@example.com']);
  });
  testWidgets('password reset uses the supplied email', (tester) async {
    final auth = TestAuth();
    await show(tester, auth);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      'reader@example.com',
    );
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(auth.calls, ['reset:reader@example.com']);
  });
  testWidgets('auth form fits a small phone with keyboard', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await show(tester, TestAuth());
    await tester.ensureVisible(find.text('Sign up'));
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('auth-submit')));
    expect(tester.takeException(), isNull);
  });
}
