// lib/backend/booking_backend.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:flutter/foundation.dart';

/// -----------------------------
/// Models & constants
/// -----------------------------
class BookingStatus {
  static const pending   = 'pending';
  static const received  = 'received';
  static const cancelled = 'cancelled';
  static const expired   = 'expired';
  static const wait      = 'wait';     // 等位
}

class Booking {
  final String id; // BookingID (B001…)
  final String userId;
  final String shopId;
  final String vehiclePlate;
  final String status;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime expiredAt;
  final List<String> slotIds;
  final List<String> serviceIds;
  final String othersText;
  final String notes;

  Booking({
    required this.id,
    required this.userId,
    required this.shopId,
    required this.vehiclePlate,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.expiredAt,
    required this.slotIds,
    required this.serviceIds,
    required this.othersText,
    required this.notes,
  });

  factory Booking.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return Booking(
      id: snap.id,
      userId: (d['UserID'] as String?) ?? '',
      shopId: (d['ShopID'] as String?) ?? '',
      vehiclePlate: (d['VehiclePlate'] as String?) ?? '',
      status: (d['Status'] as String?) ?? BookingStatus.pending,
      startAt: (d['StartAt'] as fs.Timestamp).toDate(),
      endAt: (d['EndAt'] as fs.Timestamp).toDate(),
      expiredAt: (d['ExpiredAt'] as fs.Timestamp).toDate(),
      slotIds: (d['SlotIDs'] as List?)?.cast<String>() ?? const <String>[],
      serviceIds: (d['ServiceIDs'] as List?)?.cast<String>() ?? const <String>[],
      othersText: (d['OthersText'] as String?) ?? '',
      notes: (d['Notes'] as String?) ?? '',
    );
  }
}

/// -----------------------------
/// Interface
/// -----------------------------
abstract class BookingBackend {
  static BookingBackend instance = FirebaseBookingBackend();

  /// 创建“直接占位”的 pending（必须全 Free 且容量未满；与 pending 不重叠）
  Future<String> createBooking({
    required String userId,
    required String shopId,
    required String plateNumber,
    required List<String> scheduleIds,
    required List<String> serviceIds,
    String? othersText,
    String? notes,
  });

  /// 创建等位单 wait（不占容量；允许 slot 已满；与 pending 不重叠）
  Future<String> createWaitBooking({
    required String userId,
    required String shopId,
    required String plateNumber,
    required List<String> scheduleIds,
    required List<String> serviceIds,
    String? othersText,
    String? notes,
  });

  Future<void> cancelBooking({
    required String bookingId,
    required String requestedBy,
  });

  /// 扫描所有 pending，把 ExpiredAt <= now 的置为 expired，并回退容量
  Future<int> expireOverduePendingBookings();

  /// 尝试把 wait 晋升为 pending（FIFO；在取消后或定时触发）
  Future<int> promoteWaitlistNow();

  /// 便于前端展示
  Stream<List<Booking>> watchPendingBookings(String userId);

  /// 自动任务：数据库有变更就跑 + 轻量轮询（同时做过期与等位晋升）
  void startRealtimeAutoExpire({Duration every = const Duration(seconds: 3)});
  void stopRealtimeAutoExpire();
}

/// -----------------------------
/// Firestore implementation
/// -----------------------------
class FirebaseBookingBackend implements BookingBackend {
  final fs.FirebaseFirestore _db = fs.FirebaseFirestore.instance;

  // 用 withConverter 保证泛型安全（各版本 cloud_firestore 都 OK）
  fs.CollectionReference<Map<String, dynamic>> get _colBooking =>
      _db.collection('Booking').withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (data, _) => data,
      );

  fs.CollectionReference<Map<String, dynamic>> get _colSchedule =>
      _db.collection('Schedule').withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (data, _) => data,
      );

  fs.DocumentReference<Map<String, dynamic>> get _seqDoc =>
      _db.collection('meta').doc('sequences').withConverter<Map<String, dynamic>>(
        fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
        toFirestore: (data, _) => data,
      ); // { booking: <int> }

  StreamSubscription? _rtPendingSub;
  StreamSubscription? _rtWaitSub;
  Timer? _ticker;
  bool _working = false; // 防抖（过期/晋升共用）

  /// ===== 事务里拿可读 ID：B001、B002… =====
  Future<String> _nextBookingIdInTx(fs.Transaction tx) async {
    final snap = await tx.get(_seqDoc);
    int n = 0;
    if (snap.exists) n = (snap.data()!['booking'] as num?)?.toInt() ?? 0;
    n += 1;
    tx.set(_seqDoc, {'booking': n}, fs.SetOptions(merge: true));
    return 'B${n.toString().padLeft(3, '0')}';
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 统一用毫秒时间戳比较，避免本地/UTC困扰
  bool _isExpired(DateTime? exp) {
    if (exp == null) return false;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final expMs = exp.millisecondsSinceEpoch;
    return expMs <= nowMs;
  }

  /// ===== 与“已有 pending”时间是否重叠（在事务里、任何写之前执行）=====
  Future<void> _assertNoVehicleOverlapWithPendingInTx(
      fs.Transaction tx, {
        required String plateNumber,
        required DateTime start0,
        required DateTime endN,
      }) async {
    // 需要复合索引：Booking(VehiclePlate ASC, Status ASC, StartAt ASC)
    final pre = await _colBooking
        .where('VehiclePlate', isEqualTo: plateNumber)
        .where('Status', isEqualTo: BookingStatus.pending)
        .where('StartAt', isLessThan: fs.Timestamp.fromDate(endN))
        .orderBy('StartAt')
        .get();

    // 在事务里复读这些文档，保证“所有读先于所有写”
    for (final d in pre.docs) {
      final snap = await tx.get(_colBooking.doc(d.id));
      if (!snap.exists) continue;
      final bd = snap.data()!;
      final s = (bd['StartAt'] as fs.Timestamp).toDate();
      final e = (bd['EndAt']   as fs.Timestamp).toDate();
      final overlap = s.isBefore(endN) && e.isAfter(start0); // s < endN && e > start0
      if (overlap) {
        final bid = (bd['BookingID'] as String?) ?? snap.id;
        throw Exception(
          'This vehicle already has a pending booking ($bid) from '
              '${s.toLocal()} to ${e.toLocal()}.',
        );
      }
    }
  }

  /// 校验 slots：存在、同店、同日、连续
  void _validateSameShopSameDayContiguous(
      List<fs.DocumentSnapshot<Map<String, dynamic>>> slotSnaps,
      String shopId,
      ) {
    for (final s in slotSnaps) {
      final d = s.data()!;
      if ((d['ShopID'] as String?) != shopId) {
        throw Exception('Selected slots must belong to the same shop.');
      }
    }
    slotSnaps.sort((a, b) {
      final sa = (a.data()!['StartAt'] as fs.Timestamp).toDate();
      final sb = (b.data()!['StartAt'] as fs.Timestamp).toDate();
      return sa.compareTo(sb);
    });
    final day0 = (slotSnaps.first.data()!['StartAt'] as fs.Timestamp).toDate();
    for (final s in slotSnaps) {
      final st = (s.data()!['StartAt'] as fs.Timestamp).toDate();
      final en = (s.data()!['EndAt'] as fs.Timestamp).toDate();
      if (!_sameDay(st, day0) || !_sameDay(en, day0)) {
        throw Exception('Selected slots must be on the same day.');
      }
    }
    for (int i = 0; i < slotSnaps.length - 1; i++) {
      final aEnd = (slotSnaps[i].data()!['EndAt'] as fs.Timestamp).toDate();
      final bStart = (slotSnaps[i + 1].data()!['StartAt'] as fs.Timestamp).toDate();
      if (!aEnd.isAtSameMomentAs(bStart)) {
        throw Exception('Selected slots must be back-to-back.');
      }
    }
  }

  /// 这些 slot 当前是否都能再 +1（严格要求 status=Free 且 cur < tot）
  bool _slotsAcceptOneMore(List<fs.DocumentSnapshot<Map<String, dynamic>>> slotSnaps) {
    for (final s in slotSnaps) {
      final d = s.data()!;
      final status = ((d['Status'] as String?) ?? 'Free').trim().toLowerCase();
      final cur = (d['CurrentCapacity'] as num?)?.toInt() ?? 0;
      final tot = (d['TotalCapacity'] as num?)?.toInt() ?? 3;
      if (!(status == 'free' && cur < tot)) return false;
    }
    return true;
  }

  /// 在事务里：给这些 slot 统一 +1；到顶则置 Full
  void _incrementSlotsInTx(
      fs.Transaction tx,
      List<fs.DocumentSnapshot<Map<String, dynamic>>> slotSnaps,
      ) {
    for (final s in slotSnaps) {
      final d = s.data()!;
      final sid = (d['ScheduleID'] as String?) ?? s.id;
      final sRef = _colSchedule.doc(sid);

      final cur = (d['CurrentCapacity'] as num?)?.toInt() ?? 0;
      final tot = (d['TotalCapacity'] as num?)?.toInt() ?? 3;
      final next = cur + 1;
      if (next > tot) {
        throw Exception('Time slot is full when reserving: $sid');
      }

      final update = <String, Object>{'CurrentCapacity': next};
      if (next >= tot) update['Status'] = 'Full';
      tx.update(sRef, update);
    }
  }

  @override
  Future<String> createBooking({
    required String userId,
    required String shopId,
    required String plateNumber,
    required List<String> scheduleIds,
    required List<String> serviceIds,
    String? othersText,
    String? notes,
  }) async {
    if (scheduleIds.isEmpty) {
      throw Exception('Please select at least one time slot.');
    }
    if (serviceIds.isEmpty) {
      throw Exception('Please select at least one service.');
    }

    final bookingId = await _db.runTransaction<String>((tx) async {
      // 1) 读取 slot
      final slotSnaps = <fs.DocumentSnapshot<Map<String, dynamic>>>[];
      for (final sid in scheduleIds) {
        final sSnap = await tx.get(_colSchedule.doc(sid));
        if (!sSnap.exists) throw Exception('Time slot not found: $sid');
        slotSnaps.add(sSnap);
      }

      // 2) 校验同店/同日/连续
      _validateSameShopSameDayContiguous(slotSnaps, shopId);

      final day0 = (slotSnaps.first.data()!['StartAt'] as fs.Timestamp).toDate();
      final endN = (slotSnaps.last.data()!['EndAt'] as fs.Timestamp).toDate();

      // 3) 必须都可 +1（status=Free 且 cur<tot）
      if (!_slotsAcceptOneMore(slotSnaps)) {
        throw Exception('Selected slots are not available now.');
      }

      // 4) 与“已有 pending”不重叠
      await _assertNoVehicleOverlapWithPendingInTx(
        tx,
        plateNumber: plateNumber,
        start0: day0,
        endN: endN,
      );

      // 5) 写 Booking（pending）
      final newId = await _nextBookingIdInTx(tx);
      final expiredAt = day0.add(const Duration(minutes: 30));
      final bookingRef = _colBooking.doc(newId);

      tx.set(bookingRef, {
        'BookingID'   : newId,
        'UserID'      : userId,
        'ShopID'      : shopId,
        'VehiclePlate': plateNumber,
        'Status'      : BookingStatus.pending,
        'CreatedAt'   : fs.FieldValue.serverTimestamp(),
        'StartAt'     : fs.Timestamp.fromDate(day0),
        'EndAt'       : fs.Timestamp.fromDate(endN),
        'ExpiredAt'   : fs.Timestamp.fromDate(expiredAt),
        'SlotIDs'     : scheduleIds,
        'ServiceIDs'  : serviceIds,
        if ((othersText ?? '').isNotEmpty) 'OthersText': othersText,
        'Notes'       : notes ?? '',
      });

      // 6) 占容量
      _incrementSlotsInTx(tx, slotSnaps);

      return newId;
    });

    debugPrint('[Booking] created $bookingId');
    return bookingId;
  }

  @override
  Future<String> createWaitBooking({
    required String userId,
    required String shopId,
    required String plateNumber,
    required List<String> scheduleIds,
    required List<String> serviceIds,
    String? othersText,
    String? notes,
  }) async {
    if (scheduleIds.isEmpty) {
      throw Exception('Please select at least one time slot.');
    }
    if (serviceIds.isEmpty) {
      throw Exception('Please select at least one service.');
    }

    final bookingId = await _db.runTransaction<String>((tx) async {
      // 1) 读 slots
      final slotSnaps = <fs.DocumentSnapshot<Map<String, dynamic>>>[];
      for (final sid in scheduleIds) {
        final sSnap = await tx.get(_colSchedule.doc(sid));
        if (!sSnap.exists) throw Exception('Time slot not found: $sid');
        slotSnaps.add(sSnap);
      }

      // 2) 校验同店/同日/连续（允许 Full）
      _validateSameShopSameDayContiguous(slotSnaps, shopId);

      final day0 = (slotSnaps.first.data()!['StartAt'] as fs.Timestamp).toDate();
      final endN = (slotSnaps.last.data()!['EndAt'] as fs.Timestamp).toDate();

      // 3) 与“已有 pending”不重叠（避免同车同时间重复占位）
      await _assertNoVehicleOverlapWithPendingInTx(
        tx,
        plateNumber: plateNumber,
        start0: day0,
        endN: endN,
      );

      // 4) 写 Booking（wait，不占容量）
      final newId = await _nextBookingIdInTx(tx);
      final expiredAt = day0.add(const Duration(minutes: 30)); // 保持字段一致
      final bookingRef = _colBooking.doc(newId);

      tx.set(bookingRef, {
        'BookingID'   : newId,
        'UserID'      : userId,
        'ShopID'      : shopId,
        'VehiclePlate': plateNumber,
        'Status'      : BookingStatus.wait,
        'CreatedAt'   : fs.FieldValue.serverTimestamp(),
        'StartAt'     : fs.Timestamp.fromDate(day0),
        'EndAt'       : fs.Timestamp.fromDate(endN),
        'ExpiredAt'   : fs.Timestamp.fromDate(expiredAt),
        'SlotIDs'     : scheduleIds,
        'ServiceIDs'  : serviceIds,
        if ((othersText ?? '').isNotEmpty) 'OthersText': othersText,
        'Notes'       : notes ?? '',
      });

      return newId;
    });

    debugPrint('[Booking] created WAIT $bookingId');
    return bookingId;
  }

  @override
  Future<void> cancelBooking({
    required String bookingId,
    required String requestedBy,
  }) async {
    await _db.runTransaction<void>((tx) async {
      final bRef = _colBooking.doc(bookingId);
      final bSnap = await tx.get(bRef);
      if (!bSnap.exists) throw Exception('Booking not found.');
      final bd = bSnap.data()!;
      final status = (bd['Status'] as String?) ?? BookingStatus.pending;

      final slotIds = (bd['SlotIDs'] as List?)?.cast<String>() ?? const <String>[];

      if (status == BookingStatus.pending) {
        // 回退容量
        final scheduleSnaps = <String, fs.DocumentSnapshot<Map<String, dynamic>>>{};
        for (final sid in slotIds) {
          final sSnap = await tx.get(_colSchedule.doc(sid));
          if (sSnap.exists) scheduleSnaps[sid] = sSnap;
        }
        for (final e in scheduleSnaps.entries) {
          final sid = e.key;
          final sd  = e.value.data()!;
          final cur = (sd['CurrentCapacity'] as num?)?.toInt() ?? 0;
          final tot = (sd['TotalCapacity'] as num?)?.toInt() ?? 3;
          final next = (cur - 1) < 0 ? 0 : (cur - 1);

          final update = <String, Object>{'CurrentCapacity': next};
          if (next < tot) update['Status'] = 'Free';
          tx.update(_colSchedule.doc(sid), update);
        }
      }

      tx.update(bRef, {
        'Status': BookingStatus.cancelled,
        'UpdatedAt': fs.FieldValue.serverTimestamp(),
        'CancelledBy': requestedBy,
      });
    });

    // 取消后触发一次晋升扫描（异步，不阻塞 UI）
    unawaited(promoteWaitlistNow());

    debugPrint('[Booking] cancelled $bookingId');
  }

  @override
  Future<int> expireOverduePendingBookings() async {
    final qs = await _colBooking
        .where('Status', isEqualTo: BookingStatus.pending)
        .limit(500)
        .get();

    int changed = 0;
    for (final doc in qs.docs) {
      final exp = (doc.data()['ExpiredAt'] as fs.Timestamp?)?.toDate();
      if (_isExpired(exp)) {
        try {
          await _expireOnePendingInTx(doc.id);
          changed++;
        } catch (_) {
          // ignore single failure
        }
      }
    }
    if (changed > 0) {
      debugPrint('[Booking] expired $changed pending bookings.');
    }
    return changed;
  }

  Future<void> _expireOnePendingInTx(String bookingId) async {
    await _db.runTransaction<void>((tx) async {
      final bRef = _colBooking.doc(bookingId);
      final bSnap = await tx.get(bRef);
      if (!bSnap.exists) return;

      final d = bSnap.data()!;
      if ((d['Status'] as String?) != BookingStatus.pending) return;

      final expiredAt = (d['ExpiredAt'] as fs.Timestamp?)?.toDate();
      if (!_isExpired(expiredAt)) return;

      final slotIds = (d['SlotIDs'] as List?)?.cast<String>() ?? const <String>[];

      // 回退容量
      final scheduleSnaps = <String, fs.DocumentSnapshot<Map<String, dynamic>>>{};
      for (final sid in slotIds) {
        final sSnap = await tx.get(_colSchedule.doc(sid));
        if (sSnap.exists) scheduleSnaps[sid] = sSnap;
      }
      for (final e in scheduleSnaps.entries) {
        final sid = e.key;
        final sd  = e.value.data()!;
        final cur = (sd['CurrentCapacity'] as num?)?.toInt() ?? 0;
        final tot = (sd['TotalCapacity'] as num?)?.toInt() ?? 3;
        final next = (cur - 1) < 0 ? 0 : (cur - 1);

        final update = <String, Object>{'CurrentCapacity': next};
        if (next < tot) update['Status'] = 'Free';
        tx.update(_colSchedule.doc(sid), update);
      }

      // 更新 Booking
      tx.update(bRef, {
        'Status': BookingStatus.expired,
        'UpdatedAt': fs.FieldValue.serverTimestamp(),
      });
    });
  }

  /// 尝试把部分 wait 晋升为 pending（FIFO；每次处理一批）
  @override
  Future<int> promoteWaitlistNow() async {
    final qs = await _colBooking
        .where('Status', isEqualTo: BookingStatus.wait)
        .limit(200)
        .get();

    final docs = qs.docs.toList()
      ..sort((a, b) {
        final ta = (a.data()['CreatedAt'] as fs.Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final tb = (b.data()['CreatedAt'] as fs.Timestamp?)?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb); // 先来先晋升
      });

    int promoted = 0;
    for (final d in docs) {
      try {
        await _promoteOneWaitInTx(d.id);
        promoted++;
      } catch (_) {
        // 并发/资源不足很常见，忽略继续
      }
    }

    if (promoted > 0) {
      debugPrint('[Booking] promoted $promoted wait bookings.');
    }
    return promoted;
  }

  Future<void> _promoteOneWaitInTx(String bookingId) async {
    await _db.runTransaction<void>((tx) async {
      final bRef = _colBooking.doc(bookingId);
      final bSnap = await tx.get(bRef);
      if (!bSnap.exists) return;

      final bd = bSnap.data()!;
      if ((bd['Status'] as String?) != BookingStatus.wait) return;

      final plateNumber = (bd['VehiclePlate'] as String?) ?? '';
      final shopId = (bd['ShopID'] as String?) ?? '';
      final slotIds = (bd['SlotIDs'] as List?)?.cast<String>() ?? const <String>[];

      // 读 slots
      final slotSnaps = <fs.DocumentSnapshot<Map<String, dynamic>>>[];
      for (final sid in slotIds) {
        final sSnap = await tx.get(_colSchedule.doc(sid));
        if (!sSnap.exists) return; // slot 不在了，放弃
        slotSnaps.add(sSnap);
      }

      // 校验同店/同日/连续
      _validateSameShopSameDayContiguous(slotSnaps, shopId);

      final day0 = (slotSnaps.first.data()!['StartAt'] as fs.Timestamp).toDate();
      final endN = (slotSnaps.last.data()!['EndAt'] as fs.Timestamp).toDate();

      // 必须现在都能 +1
      if (!_slotsAcceptOneMore(slotSnaps)) return;

      // 与“已有 pending”不重叠
      await _assertNoVehicleOverlapWithPendingInTx(
        tx,
        plateNumber: plateNumber,
        start0: day0,
        endN: endN,
      );

      // 改 booking → pending（ExpiredAt 保持原值，系统会在到点时自动过期）
      tx.update(bRef, {
        'Status': BookingStatus.pending,
        'UpdatedAt': fs.FieldValue.serverTimestamp(),
        'PromotedAt': fs.FieldValue.serverTimestamp(),
      });

      // 占容量
      _incrementSlotsInTx(tx, slotSnaps);
    });
  }

  @override
  Stream<List<Booking>> watchPendingBookings(String userId) {
    // 订阅时顺手扫一遍（过期 + 晋升）
    Future.microtask(() async {
      await expireOverduePendingBookings();
      await promoteWaitlistNow();
    });

    return _colBooking
        .where('UserID', isEqualTo: userId)
        .where('Status', isEqualTo: BookingStatus.pending)
        .orderBy('StartAt') // 如提示建索引，请在控制台点一下
        .snapshots()
        .map((qs) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;

      // 快照里“机会性过期”
      for (final doc in qs.docs) {
        final exp = (doc.data()['ExpiredAt'] as fs.Timestamp?)?.toDate();
        if (exp != null && exp.millisecondsSinceEpoch <= nowMs) {
          _expireOnePendingInTx(doc.id);
        }
      }

      // UI 侧先过滤掉已过期（避免闪一下）
      return qs.docs
          .where((doc) {
        final exp = (doc.data()['ExpiredAt'] as fs.Timestamp?)?.toDate();
        return exp == null || exp.millisecondsSinceEpoch > nowMs;
      })
          .map(Booking.fromSnap)
          .toList();
    });
  }

  /// 自动任务：数据库有变更就触发一次 + 每 N 秒轮询一次
  @override
  void startRealtimeAutoExpire({Duration every = const Duration(seconds: 3)}) {
    // 监听 pending 变化（新建/更新/删除）
    _rtPendingSub ??=
        _colBooking.where('Status', isEqualTo: BookingStatus.pending).snapshots().listen((_) async {
          if (_working) return;
          _working = true;
          try {
            await expireOverduePendingBookings();
            await promoteWaitlistNow();
          } finally {
            _working = false;
          }
        });

    // 监听 wait 变化（有人等位或被修改）
    _rtWaitSub ??=
        _colBooking.where('Status', isEqualTo: BookingStatus.wait).snapshots().listen((_) async {
          if (_working) return;
          _working = true;
          try {
            await promoteWaitlistNow();
          } finally {
            _working = false;
          }
        });

    // 轻量轮询（兜底）
    _ticker?.cancel();
    _ticker = Timer.periodic(every, (_) async {
      if (_working) return;
      _working = true;
      try {
        await expireOverduePendingBookings();
        await promoteWaitlistNow();
      } finally {
        _working = false;
      }
    });

    // 立即跑一次
    unawaited(expireOverduePendingBookings());
    unawaited(promoteWaitlistNow());
    debugPrint('[Booking] auto-expire/promote watchers + ticker started.');
  }

  @override
  void stopRealtimeAutoExpire() {
    _rtPendingSub?.cancel();
    _rtWaitSub?.cancel();
    _rtPendingSub = null;
    _rtWaitSub = null;
    _ticker?.cancel();
    _ticker = null;
    debugPrint('[Booking] auto-expire/promote stopped.');
  }
}
