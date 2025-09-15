import 'package:flutter/material.dart';
import 'frontend/home.dart';
import 'frontend/profile.dart'; // 内含 LoginPage / RegisterPage

class AppRouter {
  static const login = '/login';
  static const register = '/register';
  static const home = '/home';
  static const appointments = '/appointments';
  static const booking = '/booking';
  static const tracking = '/tracking';
  static const billing = '/billing';
  static const feedback = '/feedback';
  static const profile = '/profile';

  static Map<String, WidgetBuilder> routes = {
    login: (_) => const LoginPage(),
    register: (_) => const RegisterPage(),
    home: (_) => const HomePage(),

    // 其余页面先占位，后续你们再填充
    profile: (_) => const ProfilePage(),
  };
}
