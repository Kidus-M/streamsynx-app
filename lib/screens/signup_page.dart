import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_chrome.dart';
import 'auth_scaffold.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  bool _busy = false;
  bool _googleBusy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  String? _validate() {
    if (_username.text.trim().length < 3) {
      return 'Pick a username of at least three characters.';
    }
    if (!_email.text.contains('@')) return 'Enter a valid email address.';
    if (_password.text.length < 6) {
      return 'Passwords need to be at least six characters.';
    }
    return null;
  }

  Future<void> _createAccount() async {
    final problem = _validate();
    if (problem != null) {
      showAppSnack(context, problem);
      return;
    }

    setState(() => _busy = true);
    try {
      final username = _username.text.trim();

      // Usernames are how buddies find each other, so a duplicate has to be
      // caught before the account is created rather than after.
      final taken = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
      if (taken.docs.isNotEmpty) {
        if (mounted) showAppSnack(context, 'That username is taken. Try another.');
        return;
      }

      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );

      final user = result.user;
      if (user != null) {
        await user.updateDisplayName(username);
        await GoogleAuth.ensureProfile(user, username: username);
      }
      // The auth gate swaps to the app on its own once the user exists.
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

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Save titles, keep your history, and watch along with buddies.',
      children: [
        AuthField(
          controller: _username,
          label: 'Username',
          hint: 'How buddies will find you',
          icon: Icons.person_outline_rounded,
          textInputAction: TextInputAction.next,
        ),
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
          hint: 'At least six characters',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _createAccount(),
          trailing: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 19,
              color: AppColors.textSecondary,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
        const SizedBox(height: AppSpace.sm),
        FilledButton(
          onPressed: _busy ? null : _createAccount,
          child: _busy
              ? const SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create account'),
        ),
        const OrDivider(),
        GoogleButton(loading: _googleBusy, onPressed: _google),
      ],
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Already have an account?', style: AppText.bodyMuted),
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}
