import 'package:flutter/material.dart';
import 'frontend/home.dart';
import 'frontend/profile.dart';          // LoginPage / RegisterPage / ProfilePage
import 'backend/profile.dart';          // currentUser
import 'frontend/billing_pages.dart';   // billing list/detail/payment
import 'frontend/feedback_pages.dart';  // feedback form + simple list

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
    // Auth
    login: (ctx) => const LoginPage(),
    register: (ctx) => const RegisterPage(),

    // Core pages you already have
    home: (ctx) => const HomePage(),

    // New
    billing: (ctx) => const BillingListPage(),
    feedback: (ctx) => const FeedbackListPage(),

    // Profile route checks login state
    profile: (ctx) {
      if (ProfileBackend.instance.currentUser == null) {
        return LoginPage(redirectTo: profile);
      }
      return const ProfilePage();
    },
  };
}
