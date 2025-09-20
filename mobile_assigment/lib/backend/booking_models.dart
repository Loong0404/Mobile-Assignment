// lib/backend/booking_models.dart
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

enum BookingStatus { pending, received, cancelled, expired }

String bookingStatusToString(BookingStatus s) {
  switch (s) {
    case BookingStatus.pending:   return 'pending';
    case BookingStatus.received:  return 'received';
    case BookingStatus.cancelled: return 'cancelled';
    case BookingStatus.expired:   return 'expired';
  }
}

BookingStatus bookingStatusFromString(String? s) {
  switch (s) {
    case 'received':  return BookingStatus.received;
    case 'cancelled': return BookingStatus.cancelled;
    case 'expired':   return BookingStatus.expired;
    case 'pending':
    default:          return BookingStatus.pending;
  }
}

/// Booking 主表（按你的 ERD 字段命名）
class Booking {
  final String id;             // Firestore doc id (BookingID)
  final String userId;         // UserID
  final String plateNumber;    // PlateNumber
  final BookingStatus status;  // Status
  final DateTime expiredAt;    // ExpiredAt = firstStartAt + 5min
  final DateTime createdAt;    // 方便排序显示
  final DateTime firstStartAt; // 业务冗余：第一个 slot 的开始时间
  final int slotCount;         // 业务冗余：选了多少个 slot

  Booking({
    required this.id,
    required this.userId,
    required this.plateNumber,
    required this.status,
    required this.expiredAt,
    required this.createdAt,
    required this.firstStartAt,
    required this.slotCount,
  });

  factory Booking.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return Booking(
      id: snap.id,
      userId: (d['UserID'] ?? '') as String,
      plateNumber: (d['PlateNumber'] ?? '') as String,
      status: bookingStatusFromString(d['Status'] as String?),
      expiredAt: (d['ExpiredAt'] as fs.Timestamp).toDate(),
      createdAt: (d['CreatedAt'] as fs.Timestamp).toDate(),
      firstStartAt: (d['FirstStartAt'] as fs.Timestamp).toDate(),
      slotCount: (d['SlotCount'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
    'UserID': userId,
    'PlateNumber': plateNumber,
    'Status': bookingStatusToString(status),
    'ExpiredAt': fs.Timestamp.fromDate(expiredAt),
    'CreatedAt': fs.Timestamp.fromDate(createdAt),
    'FirstStartAt': fs.Timestamp.fromDate(firstStartAt),
    'SlotCount': slotCount,
  };
}

/// BookingSlot 桥表：Booking ↔ Schedule（复合键用 docId 组合）
class BookingSlot {
  final String id;          // "<BookingID>__<ScheduleID>"
  final String bookingId;   // BookingID
  final String scheduleId;  // ScheduleID

  // 冗余，便于列表展示（不是 ERD 必填）
  final DateTime startAt;
  final DateTime endAt;

  BookingSlot({
    required this.id,
    required this.bookingId,
    required this.scheduleId,
    required this.startAt,
    required this.endAt,
  });

  factory BookingSlot.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return BookingSlot(
      id: snap.id,
      bookingId: (d['BookingID'] ?? '') as String,
      scheduleId: (d['ScheduleID'] ?? '') as String,
      startAt: (d['StartAt'] as fs.Timestamp).toDate(),
      endAt: (d['EndAt'] as fs.Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
    'BookingID': bookingId,
    'ScheduleID': scheduleId,
    'StartAt': fs.Timestamp.fromDate(startAt),
    'EndAt': fs.Timestamp.fromDate(endAt),
  };
}

/// BookingDetail 桥表：Booking ↔ Service（多选服务）
/// 当 ServiceID == 'ST004'（Others）时必须有 Content
class BookingDetail {
  final String id;        // "<BookingID>__<ServiceID>"
  final String bookingId; // BookingID
  final String serviceId; // ServiceID
  final String? content;  // Others 的备注（Content 字段）

  BookingDetail({
    required this.id,
    required this.bookingId,
    required this.serviceId,
    this.content,
  });

  factory BookingDetail.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data() ?? {};
    return BookingDetail(
      id: snap.id,
      bookingId: (d['BookingID'] ?? '') as String,
      serviceId: (d['ServiceID'] ?? '') as String,
      content: d['Content'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'BookingID': bookingId,
    'ServiceID': serviceId,
    if (content != null && content!.isNotEmpty) 'Content': content,
  };
}
