import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../app_router.dart';
import '../backend/profile.dart';
import '../main.dart';
import 'notifications.dart';
import 'notifications_history.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _timer;
  StreamSubscription? _authSubscription;

  @override
  void initState() {
    super.initState();

    // Listen to authentication state changes
    _authSubscription = fb.FirebaseAuth.instance.authStateChanges().listen((_) {
      if (mounted) {
        setState(() {});
        // Check notifications when auth state changes
        WmsNotification.checkNextServiceReminder(context);
      }
    });

    // Update greeting every minute
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }

  String _getGreeting() {
    final now = DateTime.now();
    final hour = now.hour;
    if (hour < 12) {
      return 'Good Morning';
    } else if (hour < 17) {
      return 'Good Afternoon';
    } else {
      return 'Good Evening';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current user and force refresh on auth state change
    final user = ProfileBackend.instance.currentUser;

    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header / App Bar ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                decoration: BoxDecoration(
                  color: WmsApp.grabGreen,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: CircleAvatar(
                            backgroundColor: Colors.white,
                            child: Text(
                              user?.name.substring(0, 1).toUpperCase() ?? '?',
                              style: TextStyle(
                                color: WmsApp.grabGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _getGreeting(),
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                user?.name ?? 'Guest',
                                style: const TextStyle(
                                  fontSize: 20,
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            // ignore: deprecated_member_use
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(32),
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.person_outline,
                                  color: Colors.white,
                                ),
                                onPressed: () => Navigator.pushNamed(
                                  context,
                                  AppRouter.profile,
                                ),
                              ),
                              Container(
                                width: 1,
                                height: 24,
                                color: Colors.white24,
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.notifications_none,
                                  color: Colors.white,
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const NotificationHistoryPage(),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Main Services Grid ───────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                delegate: SliverChildListDelegate([
                  _buildServiceItem(
                    Icons.calendar_month_rounded,
                    'Appointments',
                    AppRouter.appointments,
                    color: const Color(0xFF1DC973), // Grab green
                  ),
                  _buildServiceItem(
                    Icons.bookmark_rounded,
                    'Booking',
                    AppRouter.booking,
                    color: const Color(0xFF00B1C9), // Cyan
                  ),
                  _buildServiceItem(
                    Icons.local_shipping_rounded,
                    'Tracking',
                    AppRouter.tracking,
                    color: const Color(0xFFFF5733), // Orange
                  ),
                  _buildServiceItem(
                    Icons.receipt_rounded,
                    'Billing',
                    AppRouter.billing,
                    color: const Color(0xFF6B45BC), // Purple
                  ),
                  _buildServiceItem(
                    Icons.rate_review,
                    'Feedback',
                    AppRouter.feedback,
                  ),
                  _buildServiceItem(Icons.person, 'Profile', AppRouter.profile),
                ]),
              ),
            ),

            // ── Promotional Banner ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
                height: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Stack(
                    children: [
                      // Gradient background
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              WmsApp.grabGreen,
                              // ignore: deprecated_member_use
                              WmsApp.grabGreen.withOpacity(0.8),
                            ],
                          ),
                        ),
                      ),
                      // Decorative circle (simplified)
                      Positioned(
                        right: -20,
                        top: -20,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // ignore: deprecated_member_use
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                      ),
                      // Content
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Limited Time',
                                      style: TextStyle(
                                        color: WmsApp.grabGreen,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Special Offers',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  const Text(
                                    'Save up to 25% on services',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                // Handle offer button tap
                              },
                              style: TextButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: WmsApp.grabGreen,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Learn More',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Recent Activities (mock) ────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent Bookings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: 3,
                        separatorBuilder: (_, __) =>
                            Divider(color: Colors.grey[300]),
                        itemBuilder: (_, i) {
                          final d = DateTime.now()
                              .add(Duration(days: i))
                              .toString();
                          return ListTile(
                            leading: const CircleAvatar(
                              backgroundColor: Colors.blue,
                              child: Icon(
                                Icons.calendar_today,
                                color: Colors.white,
                              ),
                            ),
                            title: Text('Booking ${i + 1}'),
                            subtitle: Text(
                              'Scheduled for ${d.substring(0, 10)}',
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceItem(
    IconData icon,
    String label,
    String route, {
    Color? color,
  }) {
    final iconColor = color ?? Colors.blue;
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              // ignore: deprecated_member_use
              border: Border.all(color: iconColor.withOpacity(0.2), width: 1),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: WmsApp.grabDark,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
