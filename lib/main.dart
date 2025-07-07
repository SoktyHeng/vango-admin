import 'package:admin_vango/login.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:admin_vango/dashboard.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: const FirebaseOptions(
      apiKey: "AIzaSyDuKM2Q8eMeKrVP0v5qlx3l42YLQTfrPAE",
      authDomain: "fir-vango-9e387.firebaseapp.com",
      projectId: "fir-vango-9e387",
      storageBucket: "fir-vango-9e387.appspot.com",
      messagingSenderId: "735888507369",
      appId: "1:735888507369:web:ac7c356bb7c64741310b78",
    ),
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginPage(),
        '/login': (context) => const LoginPage(),
        '/dashboard': (context) => const DashboardPage(),
      },
    );
  }
}
