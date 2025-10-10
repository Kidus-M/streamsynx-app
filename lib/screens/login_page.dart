import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'signup_page.dart';

// --- Theme Colors ---
const Color primaryColor = Color(0xFF121212);
const Color secondaryColor = Color(0xFF282828);
const Color accentColor = Color(0xFFDAA520);
const Color textPrimaryColor = Color(0xFFEAEAEA);
const Color textSecondaryColor = Color(0xFFA0A0A0);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  bool isLoading = false;
  bool isGoogleLoading = false;

  // --- Email/Password Login ---
  void login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Login failed')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- Google Sign-In ---
  Future<void> signInWithGoogle() async {
    if (!mounted) return;
    setState(() => isGoogleLoading = true);

    try {
      // STEP 1: Initialize the Google Sign-In plugin (New in v6.0)
      await GoogleSignIn.instance.initialize();

      // STEP 2: Use authenticate() instead of signIn()
      final GoogleSignInAccount? googleUser = await GoogleSignIn.instance.authenticate();

      // If the user cancels the sign-in, googleUser will be null.
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        final DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(user.uid).get();

        if (!userDoc.exists) {
          await _firestore.collection('users').doc(user.uid).set({
            'username': user.displayName ?? 'New User',
            'email': user.email,
            'avatar': user.photoURL,
            'friendUids': <String>[],
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isGoogleLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      labelText: '',
      labelStyle: const TextStyle(color: textSecondaryColor),
      filled: true,
      fillColor: secondaryColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.transparent),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: accentColor, width: 2),
      ),
    );

    return Scaffold(
      backgroundColor: primaryColor,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'StreamSynx',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  color: accentColor,
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: emailController,
                style: const TextStyle(color: textPrimaryColor),
                decoration: inputDecoration.copyWith(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                style: const TextStyle(color: textPrimaryColor),
                decoration: inputDecoration.copyWith(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              isLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: accentColor))
                  : ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: login,
                child: const Text(
                  'Login',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              isGoogleLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: accentColor))
                  : ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: textPrimaryColor,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: signInWithGoogle,
                icon: Image.asset('assets/google_logo.png', height: 20),
                label: const Text(
                  'Continue with Google',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  );
                },
                child: const Text(
                  "Don't have an account? Sign up",
                  style: TextStyle(color: textSecondaryColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
