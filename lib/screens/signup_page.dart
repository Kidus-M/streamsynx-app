import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'login_page.dart'; // Import to use theme colors

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

  void signup() async {
    // ... (Your existing signup function is fine)
    if (emailController.text.isEmpty || passwordController.text.isEmpty || usernameController.text.isEmpty) {
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
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message ?? 'Signup failed')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // --- CORRECTED GOOGLE SIGN-IN METHOD ---
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
    // ... (Your build method is fine)
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
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text( 'Create Account', textAlign: TextAlign.center, style: TextStyle( fontSize: 32, fontWeight: FontWeight.bold, color: accentColor, ),),
                const SizedBox(height: 32),
                TextField( controller: usernameController, style: const TextStyle(color: textPrimaryColor), decoration: inputDecoration.copyWith(labelText: 'Username'), ),
                const SizedBox(height: 16),
                TextField( controller: emailController, style: const TextStyle(color: textPrimaryColor), decoration: inputDecoration.copyWith(labelText: 'Email'), keyboardType: TextInputType.emailAddress, ),
                const SizedBox(height: 16),
                TextField( controller: passwordController, style: const TextStyle(color: textPrimaryColor), decoration: inputDecoration.copyWith(labelText: 'Password'), obscureText: true, ),
                const SizedBox(height: 24),
                isLoading ? const Center(child: CircularProgressIndicator(color: accentColor)) : ElevatedButton( style: ElevatedButton.styleFrom( backgroundColor: accentColor, foregroundColor: primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), ), onPressed: signup, child: const Text('Sign Up', style: TextStyle(fontWeight: FontWeight.bold)), ),
                const SizedBox(height: 16),
                isGoogleLoading ? const Center(child: CircularProgressIndicator(color: accentColor)) : ElevatedButton.icon( style: ElevatedButton.styleFrom( backgroundColor: textPrimaryColor, foregroundColor: primaryColor, padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(8), ), ), onPressed: signInWithGoogle, icon: Image.asset('assets/google_logo.png', height: 20), label: const Text('Continue with Google', style: TextStyle(fontWeight: FontWeight.bold)), ),
                const SizedBox(height: 16),
                TextButton( onPressed: () { Navigator.of(context).pop(); }, child: const Text( 'Already have an account? Sign in', style: TextStyle(color: textSecondaryColor), ),),
              ],
            ),
          ),
        ),
      ),
    );
  }
}