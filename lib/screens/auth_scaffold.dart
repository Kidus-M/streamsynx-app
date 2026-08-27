import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The frame both auth screens sit in: brand, headline, form, and a footer link.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.fields,
    required this.footer,
  });

  final String title;
  final String subtitle;
  final List<Widget> fields;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.xl, vertical: AppSpace.xxl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: AppRadius.all(13),
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: AppColors.bg, size: 26),
                      ),
                      const SizedBox(width: AppSpace.md),
                      Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Stream'),
                            TextSpan(
                              text: 'Synx',
                              style: TextStyle(color: AppColors.accent),
                            ),
                          ],
                        ),
                        style: AppText.headingLg.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  Text(title, style: AppText.display),
                  const SizedBox(height: AppSpace.sm),
                  Text(subtitle, style: AppText.bodyMuted),
                  const SizedBox(height: AppSpace.xxl),
                  ...fields,
                  const SizedBox(height: AppSpace.xl),
                  footer,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A labelled field, so both forms describe inputs the same way.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.label,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.trailing,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData? icon;
  final bool obscure;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.caption),
          const SizedBox(height: AppSpace.sm),
          TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            autocorrect: false,
            enableSuggestions: !obscure,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: icon == null
                  ? null
                  : Icon(icon, size: 19, color: AppColors.textSecondary),
              suffixIcon: trailing,
            ),
          ),
        ],
      ),
    );
  }
}

/// Continue with Google, styled to sit beside the primary action rather than
/// competing with it.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.loading, required this.onPressed});

  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: loading ? null : onPressed,
      child: loading
          ? const SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/google_logo.png', height: 18, width: 18),
                const SizedBox(width: AppSpace.md),
                const Text('Continue with Google'),
              ],
            ),
    );
  }
}

/// A rule with a word in it.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.md),
              child: Text('or', style: AppText.caption),
            ),
            Expanded(child: Divider()),
          ],
        ),
      );
}

/// Google sign-in, shared by both screens.
///
/// The profile document is created on first sign-in, because Buddies searches by
/// `username` and an account without one is invisible to everybody else.
class GoogleAuth {
  const GoogleAuth._();

  static Future<void> signIn() async {
    await GoogleSignIn.instance.initialize();
    final account = await GoogleSignIn.instance.authenticate();

    final credential = GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
    );
    final result = await FirebaseAuth.instance.signInWithCredential(credential);

    final user = result.user;
    if (user == null) return;
    await ensureProfile(user);
  }

  static Future<void> ensureProfile(User user, {String? username}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();
    if (snap.exists && (snap.data()?['username'] as String?)?.isNotEmpty == true) {
      return;
    }

    final name = username?.trim().isNotEmpty == true
        ? username!.trim()
        : (user.displayName?.trim().isNotEmpty == true
            ? user.displayName!.trim()
            : (user.email?.split('@').first ?? 'user${user.uid.substring(0, 5)}'));

    await ref.set({
      'username': name,
      'email': user.email,
      'avatar': user.photoURL,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}

/// Turns Firebase's error codes into something a person can act on.
String describeAuthError(Object error) {
  if (error is! FirebaseAuthException) return 'Something went wrong. Please try again.';

  return switch (error.code) {
    'invalid-email' => 'That email address does not look right.',
    'user-disabled' => 'This account has been disabled.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' =>
      'Email or password is incorrect.',
    'email-already-in-use' => 'An account already exists with that email.',
    'weak-password' => 'Choose a password of at least six characters.',
    'network-request-failed' => 'No connection. Check your network and try again.',
    'too-many-requests' => 'Too many attempts. Try again in a moment.',
    _ => error.message ?? 'Something went wrong. Please try again.',
  };
}
