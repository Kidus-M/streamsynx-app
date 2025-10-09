import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'login_page.dart'; // We will create this file next

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const StreamSynxApp());
}

class StreamSynxApp extends StatelessWidget {
  const StreamSynxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'StreamSynx',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        primaryColor: const Color(0xFFDAA520),
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: const LoginPage(),
    );
  }
}
