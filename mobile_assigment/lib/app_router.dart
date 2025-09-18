import 'package:flutter/material.dart';

import 'frontend/home.dart';
import 'frontend/login.dart'; // 新
import 'frontend/register.dart'; // 新
import 'frontend/profile.dart'; // 仅 ProfilePage
import 'backend/profile.dart';
import 'frontend/billing_pages.dart';
import 'frontend/feedback_pages.dart';
import 'frontend/tracking.dart';

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
    login: (ctx) => const LoginPage(),
    register: (ctx) => const RegisterPage(),
    home: (ctx) => const HomePage(),
    tracking: (ctx) => const TrackingPage(),
    billing: (ctx) => const BillingListPage(),
    feedback: (ctx) => const FeedbackListPage(),
    profile: (ctx) {
      if (ProfileBackend.instance.currentUser == null) {
        return const LoginPage(redirectTo: profile);
      }
      return const ProfilePage();
    },
  };
}
