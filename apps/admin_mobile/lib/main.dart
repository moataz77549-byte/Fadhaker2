import 'package:flutter/material.dart';

void main() {
  runApp(const FadhkurAdminMobileApp());
}

class FadhkurAdminMobileApp extends StatelessWidget {
  const FadhkurAdminMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'فذكر — إدارة العمليات',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF243B6B),
          primary: const Color(0xFF243B6B),
          secondary: const Color(0xFF2E9E9E),
        ),
      ),
      home: const AdminHomeScreen(),
    );
  }
}

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('فذكر — مراقبة النظام'),
        backgroundColor: const Color(0xFF243B6B),
        foregroundColor: Colors.white,
      ),
      body: const Center(
        child: Text(
          'بوابة عمليات فذكر السريعة',
          style: TextStyle(fontSize: 18),
        ),
      ),
    );
  }
}
