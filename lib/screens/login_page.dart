import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import 'auth_scaffold.dart';
import 'signup_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      showAppSnack(context, 'Enter your email and password.');
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      // Makes sure an older account still gets a searchable profile document.
      final user = result.user;
      if (user != null) await GoogleAuth.ensureProfile(user);
      // Routing is the auth gate's job; pushing a screen here is what used to
      // bypass the bottom-nav shell entirely.
    } on Object catch (error) {
      if (mounted) showAppSnack(context, describeAuthError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _google() async {
    setState(() => _googleBusy = true);
    try {
      await GoogleAuth.signIn();
    } on Object catch (error) {
      if (mounted) showAppSnack(context, describeAuthError(error));
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      showAppSnack(context, 'Enter your email first, then tap reset.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        showAppSnack(context, 'Reset link sent to $email', success: true);
      }
    } on Object catch (error) {
      if (mounted) showAppSnack(context, describeAuthError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to reach your watchlist, history and buddies.',
      children: [
        AuthField(
          controller: _email,
          label: 'Email',
          hint: 'you@example.com',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        AuthField(
          controller: _password,
          label: 'Password',
          hint: 'Your password',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _signIn(),
          trailing: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 19,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _resetPassword,
            child: const Text('Forgot password?'),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: _busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Sign in'),
        ),
        const OrDivider(),
        GoogleButton(loading: _googleBusy, onPressed: _google),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('New here?', style: AppText.bodyMuted),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SignupPage()),
            ),
            child: const Text('Create an account'),
          ),
        ],
      ),
    );
  }
}
