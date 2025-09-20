// lib/frontend/app_drawer.dart
//
// A small, safe Drawer used across the app.
// - Reads current user from FirebaseAuth.
// - If logged in, it also streams the user doc from Firestore to show name/photo.
// - Provides app-wide navigation entries + Sign in/out.
// - All null-safety handled; no unconditional access of displayName/email.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/material.dart';

import '../app_router.dart';
import '../backend/profile.dart';
import '../main.dart';

class WmsDrawer extends StatelessWidget {
  const WmsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = fb.FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Header (logged-in users get live Firestore info; guests see a welcome header)
            if (uid != null)
              StreamBuilder<fs.DocumentSnapshot<Map<String, dynamic>>>(
                stream: fs.FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snap) {
                  final data = snap.data?.data();
                  final name =
                      (data?['name'] as String?) ??
                      user?.displayName ??
                      'Guest';
                  final email =
                      (data?['email'] as String?) ?? user?.email ?? '';
                  final base64 = data?['photoBase64'] as String?;
                  ImageProvider? avatar;
                  if (base64 != null && base64.isNotEmpty) {
                    try {
                      avatar = MemoryImage(base64Decode(base64));
                    } catch (_) {
                      avatar = null;
                    }
                  }

                  return UserAccountsDrawerHeader(
                    decoration: const BoxDecoration(color: WmsApp.grabGreen),
                    accountName: Text(name),
                    accountEmail: Text(email),
                    currentAccountPicture: CircleAvatar(
                      backgroundImage: avatar,
                      child: avatar == null
                          ? const Icon(Icons.person, color: Colors.white)
                          : null,
                    ),
                  );
                },
              )
            else
              const DrawerHeader(
                decoration: BoxDecoration(color: WmsApp.grabGreen),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    'Welcome, guest',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),

            // Navigation entries
            _navTile(
              context,
              icon: Icons.home_outlined,
              title: 'Home',
              route: AppRouter.home,
            ),
            _navTile(
              context,
              icon: Icons.calendar_today_outlined,
              title: 'Booking',
              route: AppRouter.booking,
            ),
            _navTile(
              context,
              icon: Icons.local_shipping_outlined,
              title: 'Tracking',
              route: AppRouter.tracking,
            ),
            _navTile(
              context,
              icon: Icons.receipt_long_outlined,
              title: 'Billing',
              route: AppRouter.billing,
            ),
            _navTile(
              context,
              icon: Icons.feedback_outlined,
              title: 'Feedback',
              route: AppRouter.feedback,
            ),
            _navTile(
              context,
              icon: Icons.help_outline,
              title: 'FAQ',
              route: AppRouter.faq,
            ),
            _navTile(
              context,
              icon: Icons.person_outline,
              title: 'Profile',
              route: AppRouter.profile,
            ),

            const Spacer(),
            const Divider(),

            // Sign in/out
            if (user != null)
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: () async {
                  await ProfileBackend.instance.signOut();
                  if (!context.mounted) return;
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    AppRouter.home,
                    (r) => false,
                  );
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.login),
                title: const Text('Sign in'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.pushNamed(context, AppRouter.login);
                },
              ),
          ],
        ),
      ),
    );
  }

  // Drawer list tile builder
  ListTile _navTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String route,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        Navigator.pop(context); // close drawer
        Navigator.pushReplacementNamed(context, route);
      },
    );
  }
}
