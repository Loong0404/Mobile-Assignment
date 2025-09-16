import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart' as fb;

class NotificationHistoryPage extends StatelessWidget {
  const NotificationHistoryPage({super.key});

  Future<void> _createNotificationsCollection() async {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = fs.FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      await userDoc.set({}, fs.SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = fb.FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Please login to view notifications')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: FutureBuilder<void>(
        future: _createNotificationsCollection(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          return StreamBuilder<fs.QuerySnapshot>(
            stream: fs.FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .collection('notifications') // 使用子集合
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                if (kDebugMode) {
                  print('Error: ${snapshot.error}');
                } // 添加错误日志
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_none,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final notifications = snapshot.data!.docs;
              if (notifications.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.notifications_off,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No notifications yet',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final notification =
                      notifications[index].data() as Map<String, dynamic>;
                  final timestamp = (notification['timestamp'] as fs.Timestamp)
                      .toDate();

                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        child: Icon(Icons.notifications),
                      ),
                      title: Text(notification['title'] ?? 'Service Reminder'),
                      subtitle: Text(notification['message'] ?? ''),
                      trailing: Text(
                        '${timestamp.year}-${timestamp.month.toString().padLeft(2, '0')}-${timestamp.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
