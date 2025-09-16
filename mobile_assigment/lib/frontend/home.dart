import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import '../app_router.dart';
import '../backend/profile.dart';
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
    _authSubscription = fb.FirebaseAuth.instance
        .authStateChanges()
        .listen((_) {
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
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.grey[200],
                      child: Text(
                        user?.name.substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
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
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            user?.name ?? 'Guest',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.person_outline),
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRouter.profile),
                    ),
                    IconButton(
                      icon: const Icon(Icons.notifications_none),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationHistoryPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // ── Search Bar ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const TextField(
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search for services...',
                      icon: Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            ),

            // ── Main Services Grid ───────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                ),
                delegate: SliverChildListDelegate([
                  _buildServiceItem(
                    Icons.medical_services,
                    'Appointments',
                    AppRouter.appointments,
                  ),
                  _buildServiceItem(
                    Icons.book_online,
                    'Booking',
                    AppRouter.booking,
                  ),
                  _buildServiceItem(
                    Icons.local_shipping,
                    'Tracking',
                    AppRouter.tracking,
                  ),
                  _buildServiceItem(
                    Icons.receipt_long,
                    'Billing',
                    AppRouter.billing,
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  height: 160,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.blue[100],
                  ),
                  child: const Center(
                    child: Text(
                      'Special Offers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // ── Recent Activities (mock) ────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(16),
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

  Widget _buildServiceItem(IconData icon, String label, String route) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.blue),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

