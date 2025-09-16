import 'package:flutter/material.dart';
import 'frontend/home.dart';
import 'frontend/profile.dart'; // 内含 LoginPage / RegisterPage / ProfilePage
import 'backend/profile.dart'; // ⬅️ 为了读取 currentUser
import 'frontend/billing.dart';
import 'frontend/feedback.dart';

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
    billing: (ctx) => const BillingListPage(),
    feedback: (_) => const FeedbackListPage(),
    // Profile路由处理：检查登录状态
    profile: (ctx) {
      // 如果未登录，导航到登录页面，并设置redirectTo为profile
      if (ProfileBackend.instance.currentUser == null) {
        // 显示登录页面，并设置登录成功后返回profile页面
        return LoginPage(redirectTo: profile);
      }
      // 已登录则显示个人资料页
      return const ProfilePage();
    },
  };
}
