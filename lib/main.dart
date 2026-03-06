import 'package:flutter/material.dart';
import 'package:frontend_dataforninjafruit/screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/bluetooth_pairing_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Login & Registration',
      theme: AppTheme.light(),
      debugShowCheckedModeBanner: false,
      initialRoute: '/login',
      routes: {
        '/login': (_) => const LoginScreen(),
        '/pairing': (_) => const BluetoothPairingScreen(),
        '/home': (_) => const HomeScreen(),
      },
    );
  }
}
