// lib/frontend/notifications.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class WmsNotification {
  static const int reminderWindowDays = 7;

  // 跟踪每个用户的最后通知时间
  static final Map<String, DateTime> _lastNotificationTime = {};

  /// Save notification to Firestore for history
  static Future<void> _saveNotification(
    String userId,
    String title,
    String message,
  ) async {
    // 确保用户文档存在
    final userRef = fs.FirebaseFirestore.instance
        .collection('users')
        .doc(userId);

    try {
      // 1. 检查最近12小时内是否已经有相同的通知
      final now = DateTime.now();
      final twelveHoursAgo = now.subtract(const Duration(hours: 12));

      final existingNotifications = await userRef
          .collection('notifications')
          .where('title', isEqualTo: title)
          .where('message', isEqualTo: message)
          .where('timestamp', isGreaterThan: twelveHoursAgo)
          .get();

      // 如果已经有相同的通知，不再保存
      if (existingNotifications.docs.isNotEmpty) {
        if (kDebugMode) {
          print('Similar notification exists within 12 hours, skipping...');
        }
        return;
      }

      // 2. 使用批处理来确保原子性
      final batch = fs.FirebaseFirestore.instance.batch();

      // 3. 确保用户文档存在
      batch.set(userRef, {
        'hasNotifications': true,
        'lastChecked': fs.FieldValue.serverTimestamp(),
      }, fs.SetOptions(merge: true));

      // 4. 添加通知到用户的通知子集合
      final notificationRef = userRef.collection('notifications').doc();
      batch.set(notificationRef, {
        'title': title,
        'message': message,
        'timestamp': fs.FieldValue.serverTimestamp(),
        'read': false,
      });

      // 5. 提交批处理
      await batch.commit();
      if (kDebugMode) {
        print('Notification saved successfully');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving notification: $e');
      }
    }
  }

  /// 在進入 Home 後調用。若下次保養 ≤ 7 天，彈出提醒。
  static Future<void> checkNextServiceReminder(BuildContext context) async {
    if (!context.mounted) return;

    final currentUser = fb.FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    // 检查是否需要显示通知（避免频繁显示）
    final lastTime = _lastNotificationTime[currentUser.uid];
    final now = DateTime.now();
    if (lastTime != null) {
      final diff = now.difference(lastTime);
      if (diff.inHours < 1) {
        // 每小时最多显示一次
        return;
      }
    }

    final next = await _getNextServiceDate();
    if (next == null) return;

    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final diffDays = next.difference(today0).inDays;

    if (diffDays <= reminderWindowDays) {
      final whenText = _human(next);
      final status = diffDays > 0
          ? 'in $diffDays day${diffDays == 1 ? '' : 's'}'
          : (diffDays == 0 ? 'today' : 'overdue by ${-diffDays} days');

      // Save to notification history
      final message =
          'Your next service is $status: $whenText.\nPlease plan your workshop visit.';
      await _saveNotification(currentUser.uid, 'Service Reminder', message);

      // 更新最后通知时间
      _lastNotificationTime[currentUser.uid] = DateTime.now();

      if (!context.mounted) return;
      await showDialog<void>(
        // ignore: use_build_context_synchronously
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Service reminder'),
          content: Text(
            'Your next service is $status: $whenText.\n'
            'Please plan your workshop visit.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                // 這裡可導向你的 Booking/Appointment 頁
                // Navigator.pushNamed(context, AppRouter.booking);
              },
              child: const Text('Book now'),
            ),
          ],
        ),
      );
    }
  }

  /// 先嘗試從 Firestore 讀 users/{uid}.nextServiceAt（Timestamp 或 ISO String）
  /// 若沒有，退回 demo：最近一次硬編碼 service + 365 天
  static Future<DateTime?> _getNextServiceDate() async {
    final u = fb.FirebaseAuth.instance.currentUser;
    if (u != null) {
      try {
        final doc = await fs.FirebaseFirestore.instance
            .collection('users')
            .doc(u.uid)
            .get();
        final data = doc.data();
        if (data != null) {
          final v = data['nextServiceAt'];
          if (v is fs.Timestamp) return v.toDate();
          if (v is String) {
            final parsed = DateTime.tryParse(v);
            if (parsed != null) return parsed;
          }
        }
      } catch (_) {
        /* ignore, fallback below */
      }
    }
    return _fallbackFromDemoHistory();
  }

  /// 與 Profile 一致的 demo 歷史：最近一次 + 365 天
  static DateTime? _fallbackFromDemoHistory() {
    final history = <DateTime>[
      DateTime(2024, 9, 20), // 更新为测试日期
    ]..sort((a, b) => b.compareTo(a));
    if (history.isEmpty) return null;
    final nextService = history.first.add(const Duration(days: 365));

    // Debug log
    if (kDebugMode) {
      print('Next service date: $nextService');
    }
    final now = DateTime.now();
    final diff = nextService.difference(now).inDays;
    if (kDebugMode) {
      print('Days until next service: $diff');
    }

    return nextService;
  }

  static String _human(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
