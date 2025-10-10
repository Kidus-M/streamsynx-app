import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_page.dart';
import 'home_screen.dart';

// Import theme colors from login page for consistency
const Color primaryColor = Color(0xFF121212);
const Color secondaryColor = Color(0xFF282828);
const Color accentColor = Color(0xFFDAA520);
const Color textPrimaryColor = Color(0xFFEAEAEA);
const Color textSecondaryColor = Color(0xFFA0A0A0);

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController usernameController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  bool isLoading = false;
  bool isGoogleLoading = false;

  // --- Email/Password Signup ---
  void signup() async {
    if (emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        usernameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields.')),
      );
      return;
    }
    setState(() => isLoading = true);

    try {
      UserCredential userCred = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      await userCred.user?.updateDisplayName(usernameController.text.trim());
      await _firestore.collection('users').doc(userCred.user!.uid).set({
        'username': usernameController.text.trim(),
        'email': emailController.text.trim(),
        'avatar': null,
        'friendUids': [],
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Signup failed')),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // --- Google Sign-In (Firebase v6-compatible) ---
  Future<void> signInWithGoogle() async {
    if (!mounted) return;
    setState(() => isGoogleLoading = true);

    try {
      await GoogleSignIn.instance.initialize();

      final GoogleSignInAccount googleUser =
      await GoogleSignIn.instance.authenticate();

      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth =
      googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
      await _auth.signInWithCredential(credential);
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

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google Sign-In failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: secondaryColor,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Create Account',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: accentColor),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: usernameController,
                style: const TextStyle(color: textPrimaryColor),
                decoration: inputDecoration.copyWith(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                style: const TextStyle(color: textPrimaryColor),
                decoration: inputDecoration.copyWith(labelText: 'Email'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                style: const TextStyle(color: textPrimaryColor),
                obscureText: true,
                decoration: inputDecoration.copyWith(labelText: 'Password'),
              ),
              const SizedBox(height: 24),
              isLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: accentColor))
                  : ElevatedButton(
                  onPressed: signup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Sign Up',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              isGoogleLoading
                  ? const Center(
                  child: CircularProgressIndicator(color: accentColor))
                  : ElevatedButton.icon(
                onPressed: signInWithGoogle,
                icon: Image.asset('assets/google_logo.png', height: 20),
                label: const Text('Continue with Google',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: textPrimaryColor,
                  foregroundColor: primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Already have an account? Sign in',
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
