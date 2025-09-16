import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app_router.dart';
import 'frontend/home.dart';
import 'backend/profile.dart' as prof;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Set persistence to LOCAL (this ensures login state persists across app restarts)
  await Firebase.initializeApp();

  // Initialize ProfileBackend
  prof.ProfileBackend.instance = prof.FirebaseProfileBackend();

  runApp(const WmsApp());
}

// 创建一个新的widget来处理认证状态
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomePage(); // 直接返回HomePage
  }
}

class WmsApp extends StatelessWidget {
  const WmsApp({super.key});

  static const grabGreen = Color(0xFF00B14F);
  static const grabDark = Color(0xFF363A45);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: grabGreen,
      brightness: Brightness.light,
    );

    return MaterialApp(
      title: 'WMS Customer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: Colors.white,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: grabGreen),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: grabGreen,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            // ignore: deprecated_member_use
            borderSide: BorderSide(color: grabDark.withOpacity(.15)),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
            borderSide: BorderSide(color: grabGreen, width: 1.4),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
        ),
      ),
      initialRoute: AppRouter.home, // 默认显示首页
      routes: AppRouter.routes,
    );
  }
}
