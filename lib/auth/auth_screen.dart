import 'package:flutter/material.dart';
import 'auth_client.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({required this.client, super.key});
  final AuthClient client;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  String? _notice;

  String? _validateEmail(String? value) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value?.trim() ?? '')
      ? null
      : 'Enter a valid email address.';

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      if (_signUp) {
        await widget.client.signUp(_email.text.trim(), _password.text);
      } else {
        await widget.client.signIn(_email.text.trim(), _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reset() async {
    if (_busy) return;
    final error = _validateEmail(_email.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await widget.client.resetPassword(_email.text.trim());
      if (mounted) {
        setState(
          () => _notice =
              'If this email has an account, a password reset link will be sent.',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142747), Color(0xFF030712), Color(0xFF081D26)],
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.public,
                        size: 60,
                        color: Color(0xFF93C5FD),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'GLOBE NEWS',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          letterSpacing: 4,
                          color: Color(0xFF93C5FD),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        _signUp
                            ? 'Your world. Your neighbourhood.'
                            : 'Welcome back.',
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _signUp
                            ? 'Create an account, then choose your city or state and the news radius you want to follow.'
                            : 'Sign in to follow the places that matter to you.',
                        style: const TextStyle(
                          color: Colors.white70,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Sign in')),
                          ButtonSegment(value: true, label: Text('Sign up')),
                        ],
                        selected: {_signUp},
                        showSelectedIcon: false,
                        onSelectionChanged: _busy
                            ? null
                            : (values) => setState(() {
                                _signUp = values.first;
                                _error = null;
                                _notice = null;
                                _password.clear();
                                _confirmation.clear();
                                _form.currentState?.reset();
                              }),
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: const Key('auth-email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                          border: OutlineInputBorder(),
                        ),
                        validator: _validateEmail,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const Key('auth-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: [
                          _signUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        textInputAction: _signUp
                            ? TextInputAction.next
                            : TextInputAction.done,
                        onFieldSubmitted: (_) {
                          if (!_signUp) _submit();
                        },
                        decoration: InputDecoration(
                          labelText: 'Password',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Show password'
                                : 'Hide password',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (value) => (value ?? '').isEmpty
                            ? 'Enter your password.'
                            : _signUp && value!.length < 8
                            ? 'Use at least 8 characters.'
                            : null,
                      ),
                      if (_signUp) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('auth-confirm'),
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: _obscure,
                          autocorrect: false,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) => value != _password.text
                              ? 'Passwords do not match.'
                              : null,
                        ),
                      ] else
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: _busy ? null : _reset,
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFFCA5A5)),
                          ),
                        ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_notice!),
                        ),
                      const SizedBox(height: 18),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: _busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        child: _busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_signUp ? 'Create account' : 'Sign in'),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Choose where your news comes from. No background location tracking.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
