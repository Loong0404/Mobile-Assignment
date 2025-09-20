import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

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

  factory Schedule.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return Schedule(
      id: snap.id,
      scheduleId: (d['ScheduleID'] as String?) ?? snap.id,
      shopId: (d['ShopID'] as String?) ?? '',
      startAt: (d['StartAt'] as fs.Timestamp).toDate(),
      endAt: (d['EndAt'] as fs.Timestamp).toDate(),
      status: (d['Status'] as String?) ?? 'Free',
      currentCapacity: (d['CurrentCapacity'] as num?)?.toInt() ?? 0,
      totalCapacity: (d['TotalCapacity'] as num?)?.toInt() ?? 3,
    );
  }
}

class _ShopLite {
  final String shopId;
  final String openAt;      // "10:00:00"
  final String closeAt;     // "20:00:00"
  final String status;      // "Open"/"Closed"
  final String workingDays; // "Mon-Sun"
  _ShopLite({
    required this.shopId,
    required this.openAt,
    required this.closeAt,
    required this.status,
    required this.workingDays,
  });
}

abstract class ScheduleView {
  static ScheduleView instance = _FirebaseScheduleService();

  Stream<List<Schedule>> watchForShopOnDate({
    required String shopId,
    required DateTime dayStart,
  });

  Stream<List<Schedule>> watchForShopInRange({
    required String shopId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  });
}

abstract class ScheduleUpdater {
  static ScheduleUpdater instance = _FirebaseScheduleService();

  Future<void> bootstrapAtLaunch();                 // 明天起 3 天
  Future<void> generateNextNDaysForAllShops(int n); // 明天起 n 天
  Future<void> ensure3DaysForShopIfMissing(String shopId);
}

/// 仅用于暴露调试钩子（手动写一条测试记录）
abstract class DebugHooks {
  Future<void> debugWriteOneTestSlot(String shopId);
}

class _FirebaseScheduleService
    implements ScheduleView, ScheduleUpdater, DebugHooks {
  final fs.CollectionReference<Map<String, dynamic>> _scheduleCol =
  fs.FirebaseFirestore.instance.collection('Schedule');
  final fs.CollectionReference<Map<String, dynamic>> _shopCol =
  fs.FirebaseFirestore.instance.collection('Shop');

  void _log(String m) => debugPrint('[Schedule] $m');
  DateTime _dayStart(DateTime d) => DateTime(d.year, d.month, d.day);

  static final _weekdayMap = {
    'mon': 1, 'tue': 2, 'wed': 3, 'thu': 4, 'fri': 5, 'sat': 6, 'sun': 7,
  };
  Set<int> _parseDays(String s) {
    final out = <int>{};
    final text = s.trim().toLowerCase();
    if (text.isEmpty) return out;
    for (final part in text.split(',')) {
      final p = part.trim();
      if (p.contains('-')) {
        final a = p.split('-').map((e) => e.trim()).toList();
        if (a.length == 2 && _weekdayMap.containsKey(a[0]) && _weekdayMap.containsKey(a[1])) {
          int st = _weekdayMap[a[0]]!, ed = _weekdayMap[a[1]]!;
          if (st <= ed) { for (int i = st; i <= ed; i++) out.add(i); }
          else { for (int i = st; i <= 7; i++) out.add(i); for (int i = 1; i <= ed; i++) out.add(i); }
        }
      } else if (_weekdayMap.containsKey(p)) out.add(_weekdayMap[p]!);
    }
    return out;
  }

  int _toMinutes(String hhmmss) {
    final p = hhmmss.split(':');
    final h = int.tryParse(p.elementAt(0)) ?? 0;
    final m = int.tryParse(p.elementAt(1)) ?? 0;
    return h * 60 + m;
  }
  DateTime _timeOnDate(DateTime day, String hhmmss) {
    final mins = _toMinutes(hhmmss);
    return DateTime(day.year, day.month, day.day, mins ~/ 60, mins % 60);
  }
  String _sid(String shopId, DateTime start, DateTime end) {
    final d = DateFormat('yyyyMMdd').format(start);
    final sh = DateFormat('HHmm').format(start);
    final eh = DateFormat('HHmm').format(end);
    return 'SC_${shopId}_${d}_${sh}-${eh}';
  }

  // ===== 视图 =====
  @override
  Stream<List<Schedule>> watchForShopOnDate({
    required String shopId,
    required DateTime dayStart,
  }) {
    final dayEnd = _dayStart(dayStart).add(const Duration(days: 1));
    return watchForShopInRange(
      shopId: shopId,
      startInclusive: dayStart,
      endExclusive: dayEnd,
    );
  }

  @override
  Stream<List<Schedule>> watchForShopInRange({
    required String shopId,
    required DateTime startInclusive,
    required DateTime endExclusive,
  }) {
    return _scheduleCol
        .where('ShopID', isEqualTo: shopId)
        .where('StartAt', isGreaterThanOrEqualTo: fs.Timestamp.fromDate(startInclusive))
        .where('StartAt', isLessThan: fs.Timestamp.fromDate(endExclusive))
        .orderBy('StartAt')
        .snapshots()
        .map((qs) => qs.docs.map(Schedule.fromSnap).toList());
  }

  // ===== 写入（生成）=====
  Future<List<_ShopLite>> _fetchAllShops() async {
    final qs = await _shopCol.get();
    return qs.docs.map((doc) {
      final m = doc.data();
      return _ShopLite(
        shopId: (m['ShopID'] ?? m['ShopId'] ?? m['shopId'] ?? doc.id).toString(),
        openAt: (m['OpenAt'] ?? '10:00:00').toString(),
        closeAt: (m['CloseAt'] ?? '20:00:00').toString(),
        status: (m['Status'] ?? 'Open').toString(),
        workingDays: (m['WorkingDays'] ?? 'Mon-Sun').toString(),
      );
    }).toList();
  }

  Future<void> _generateForSingleShopOnDay(
      _ShopLite shop,
      DateTime day, {
        required bool clearBefore,
      }) async {
    final days = _parseDays(shop.workingDays);
    final isWorkingDay = days.isEmpty || days.contains(day.weekday);
    if (shop.status.toLowerCase() != 'open' || !isWorkingDay) {
      _log('skip ${shop.shopId} ${DateFormat('yyyy-MM-dd').format(day)} status=${shop.status} wd="${shop.workingDays}"');
      return;
    }

    final openDt  = _timeOnDate(day, shop.openAt);
    final closeDt = _timeOnDate(day, shop.closeAt);
    if (!closeDt.isAfter(openDt)) {
      _log('skip ${shop.shopId} invalid hours ${shop.openAt}..${shop.closeAt}');
      return;
    }

    if (clearBefore) {
      final start = _dayStart(day), end = start.add(const Duration(days: 1));
      final old = await _scheduleCol
          .where('ShopID', isEqualTo: shop.shopId)
          .where('StartAt', isGreaterThanOrEqualTo: fs.Timestamp.fromDate(start))
          .where('StartAt', isLessThan: fs.Timestamp.fromDate(end))
          .get();
      if (old.docs.isNotEmpty) {
        final b = fs.FirebaseFirestore.instance.batch();
        for (final d in old.docs) { b.delete(d.reference); }
        await b.commit();
      }
    }

    const slotMin = 60;
    int count = 0;
    final batch = fs.FirebaseFirestore.instance.batch();

    DateTime s = openDt;
    while (true) {
      final e = s.add(const Duration(minutes: slotMin));
      if (e.isAfter(closeDt)) break;
      final id = _sid(shop.shopId, s, e);
      batch.set(_scheduleCol.doc(id), {
        'ScheduleID': id,
        'ShopID': shop.shopId,
        'StartAt': fs.Timestamp.fromDate(s),
        'EndAt': fs.Timestamp.fromDate(e),
        'Status': 'Free',
        'CurrentCapacity': 0,
        'TotalCapacity': 3,
      }, fs.SetOptions(merge: true));
      count++;
      s = e;
    }

    if (count == 0) {
      _log('no slots for ${shop.shopId} ${DateFormat('yyyy-MM-dd').format(day)}');
      return;
    }
    await batch.commit();
    _log('generated $count slot(s) for ${shop.shopId} ${DateFormat('yyyy-MM-dd').format(day)}');
  }

  Future<void> _generateForAllShopsOnDate(
      DateTime day, {
        required bool clearBefore,
      }) async {
    final shops = await _fetchAllShops();
    if (shops.isEmpty) { _log('no shops found'); return; }
    for (final s in shops) {
      await _generateForSingleShopOnDay(s, day, clearBefore: clearBefore);
    }
  }

  // ===== 对外 =====
  @override
  Future<void> bootstrapAtLaunch() async {
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
    } catch (_) {}

    final today = _dayStart(DateTime.now());
    final start = today.add(const Duration(days: 1)); // 明天
    for (int i = 0; i < 3; i++) {
      await _generateForAllShopsOnDate(start.add(Duration(days: i)), clearBefore: true);
    }
  }

  @override
  Future<void> generateNextNDaysForAllShops(int n) async {
    final today = _dayStart(DateTime.now());
    final start = today.add(const Duration(days: 1));
    for (int i = 0; i < n; i++) {
      await _generateForAllShopsOnDate(start.add(Duration(days: i)), clearBefore: true);
    }
  }

  @override
  Future<void> ensure3DaysForShopIfMissing(String shopId) async {
    final qs = await _shopCol.where('ShopID', isEqualTo: shopId).limit(1).get();
    if (qs.docs.isEmpty) throw Exception('Shop not found: $shopId');

    final m = qs.docs.first.data();
    final shop = _ShopLite(
      shopId: (m['ShopID'] ?? shopId).toString(),
      openAt: (m['OpenAt'] ?? '10:00:00').toString(),
      closeAt: (m['CloseAt'] ?? '20:00:00').toString(),
      status: (m['Status'] ?? 'Open').toString(),
      workingDays: (m['WorkingDays'] ?? 'Mon-Sun').toString(),
    );

    final today = _dayStart(DateTime.now());
    final start = today.add(const Duration(days: 1));
    for (int i = 0; i < 3; i++) {
      await _generateForSingleShopOnDay(shop, start.add(Duration(days: i)), clearBefore: false);
    }
  }

  // ===== 调试钩子：直接写一条“明天 10:00–11:00”的测试数据 =====
  @override
  Future<void> debugWriteOneTestSlot(String shopId) async {
    final t = _dayStart(DateTime.now()).add(const Duration(days: 1));
    final s = DateTime(t.year, t.month, t.day, 10, 0, 0);
    final e = s.add(const Duration(hours: 1));
    final id = _sid(shopId, s, e);
    await _scheduleCol.doc(id).set({
      'ScheduleID': id,
      'ShopID': shopId,
      'StartAt': fs.Timestamp.fromDate(s),
      'EndAt': fs.Timestamp.fromDate(e),
      'Status': 'Free',
      'CurrentCapacity': 0,
      'TotalCapacity': 3,
    }, fs.SetOptions(merge: true));
    _log('debug wrote one TEST slot for $shopId');
  }
}
