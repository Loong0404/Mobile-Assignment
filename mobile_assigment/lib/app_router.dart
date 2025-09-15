import 'package:flutter/material.dart';
import 'frontend/home.dart';
import 'frontend/profile.dart'; // 内含 LoginPage / RegisterPage / ProfilePage
import 'backend/profile.dart'; // ⬅️ 为了读取 currentUser

class AppRouter {
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const appointments = '/appointments';
  static const booking = '/booking';
  static const tracking = '/tracking';
  static const billing = '/billing';
  static const feedback = '/feedback';
  static const notices = '/notices';
  static const profile = '/profile';

  static Map<String, WidgetBuilder> routes = {
    login: (ctx) => const LoginPage(), // 可被带参复用（见下方 /profile）
    register: (ctx) => const RegisterPage(),
    home: (ctx) => const HomePage(),

    // ⬇️ 关键：访问 /profile 时做「登录守卫」
    profile: (ctx) {
      final signedIn = ProfileBackend.instance.currentUser != null;
      if (signedIn) {
        return const ProfilePage();
      } else {
        // 未登录就先去登录；登录后自动跳回 /profile
        return const LoginPage(redirectTo: profile);
      }
    },
  };
}
