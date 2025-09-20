import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class Schedule {
  final String id;
  final String scheduleId;
  final String shopId;
  final DateTime startAt;
  final DateTime endAt;
  final String status;
  final int currentCapacity;
  final int totalCapacity;

  Schedule({
    required this.id,
    required this.scheduleId,
    required this.shopId,
    required this.startAt,
    required this.endAt,
    required this.status,
    required this.currentCapacity,
    required this.totalCapacity,
  });

  factory Schedule.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Schedule(
      id: s.id,
      scheduleId: (d['ScheduleID'] as String?) ?? s.id,
      shopId: (d['ShopID'] as String?) ?? '',
      startAt: (d['StartAt'] as fs.Timestamp).toDate(),
      endAt: (d['EndAt'] as fs.Timestamp).toDate(),
      status: (d['Status'] as String?) ?? 'Free',
      currentCapacity: (d['CurrentCapacity'] as num?)?.toInt() ?? 0,
      totalCapacity: (d['TotalCapacity'] as num?)?.toInt() ?? 3,
    );
  }
}

abstract class ScheduleViewBackend {
  static ScheduleViewBackend instance = FirebaseScheduleViewBackend();

  Stream<List<Schedule>> watchForShopInRange({
    required String shopId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  });
}

class FirebaseScheduleViewBackend implements ScheduleViewBackend {
  final fs.CollectionReference<Map<String, dynamic>> col =
  fs.FirebaseFirestore.instance.collection('Schedule');

  @override
  Stream<List<Schedule>> watchForShopInRange({
    required String shopId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    // 需要复合索引：ShopID + StartAt 升序
    return col
        .where('ShopID', isEqualTo: shopId)
        .where('StartAt', isGreaterThanOrEqualTo: fs.Timestamp.fromDate(startInclusive))
        .where('StartAt', isLessThan: fs.Timestamp.fromDate(endExclusive))
        .orderBy('StartAt')
        .snapshots()
        .map((q) => q.docs.map(Schedule.fromSnap).toList());
  }
}
