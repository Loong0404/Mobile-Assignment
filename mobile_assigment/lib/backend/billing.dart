import 'dart:async';

enum BillStatus { pending, paid }

class Bill {
  final String id;
  final String userId;
  final String plate;
  final DateTime createdAt;
  final double amount;
  BillStatus status;

  Bill({
    required this.id,
    required this.userId,
    required this.plate,
    required this.createdAt,
    required this.amount,
    required this.status,
  });
}

class Payment {
  final String id;
  final String billId;
  final String userId;
  final DateTime paidAt;
  final double amount;
  final String method;   // e.g. 'Card', 'FPX', 'eWallet'
  final String txnRef;   // simulated reference

  Payment({
    required this.id,
    required this.billId,
    required this.userId,
    required this.paidAt,
    required this.amount,
    required this.method,
    required this.txnRef,
  });
}

/// Feedback (1–5 stars) for a paid bill
class FeedbackEntry {
  final String id;
  final String billId;
  final String userId;
  int rating;               // 1..5
  String comment;           // free text
  DateTime createdAt;       // when submitted/updated

  FeedbackEntry({
    required this.id,
    required this.billId,
    required this.userId,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });
}

/// Replace this with a Firebase-backed implementation later.
/// Keep method signatures the same and your UI won't need to change.
abstract class BillingBackend {
  static BillingBackend instance = _InMemoryBillingBackend._();

  // Bills & payments
  Stream<List<Bill>> watchBillsForUser(String userId);
  Future<List<Bill>> getBillsForUser(String userId);
  Future<Bill?> getBill(String billId);
  Future<Payment> payBill({
    required String billId,
    required String userId,
    required String method,
  });

  // Feedback
  Stream<List<FeedbackEntry>> watchFeedbacksForUser(String userId);
  Future<FeedbackEntry?> getFeedbackForBill({
    required String billId,
    required String userId,
  });
  Future<FeedbackEntry> submitFeedback({
    required String billId,
    required String userId,
    required int rating,
    required String comment,
  });
}

class _InMemoryBillingBackend implements BillingBackend {
  _InMemoryBillingBackend._() {
    // Build controllers that re-emit latest on new listeners
    _billCtrl = StreamController<List<Bill>>.broadcast(onListen: _emitBills);
    _fbCtrl   = StreamController<List<FeedbackEntry>>.broadcast(onListen: _emitFeedback);

    // Seed demo data
    final now = DateTime.now();
    _bills.addAll([
      Bill(
        id: 'B-1001',
        userId: 'u1',
        plate: 'VBA1234',
        createdAt: now.subtract(const Duration(days: 5)),
        amount: 120.00,
        status: BillStatus.pending,
      ),
      Bill(
        id: 'B-1002',
        userId: 'u1',
        plate: 'VBA1234',
        createdAt: now.subtract(const Duration(days: 2)),
        amount: 80.50,
        status: BillStatus.paid,
      ),
      Bill(
        id: 'B-2001',
        userId: 'u2',
        plate: 'WXY5678',
        createdAt: now.subtract(const Duration(days: 1)),
        amount: 60.00,
        status: BillStatus.pending,
      ),
    ]);

    // Demo: one feedback already left for B-1002
    _feedbacks.add(
      FeedbackEntry(
        id: 'F-1',
        billId: 'B-1002',
        userId: 'u1',
        rating: 5,
        comment: 'Smooth payment & quick confirmation.',
        createdAt: now.subtract(const Duration(days: 1)),
      ),
    );

    _emitBills();
    _emitFeedback();
  }

  final _bills = <Bill>[];
  final _payments = <Payment>[];
  final _feedbacks = <FeedbackEntry>[];

  late final StreamController<List<Bill>> _billCtrl;
  late final StreamController<List<FeedbackEntry>> _fbCtrl;

  void _emitBills()   => _billCtrl.add(List.unmodifiable(_bills));
  void _emitFeedback()=> _fbCtrl.add(List.unmodifiable(_feedbacks));

  // ---------------- Bills ----------------
  @override
  Stream<List<Bill>> watchBillsForUser(String userId) =>
      _billCtrl.stream.map((list) => list.where((b) => b.userId == userId).toList());

  @override
  Future<List<Bill>> getBillsForUser(String userId) async =>
      _bills.where((b) => b.userId == userId).toList();

  @override
  Future<Bill?> getBill(String billId) async {
    final idx = _bills.indexWhere((b) => b.id == billId);
    if (idx == -1) return null;
    return _bills[idx];
  }

  @override
  Future<Payment> payBill({
    required String billId,
    required String userId,
    required String method,
  }) async {
    // Simulate processing
    await Future.delayed(const Duration(milliseconds: 800));

    final bill = _bills.firstWhere((b) => b.id == billId);
    if (bill.status == BillStatus.paid) {
      // Idempotent
      return _payments.firstWhere((p) => p.billId == billId);
    }

    bill.status = BillStatus.paid;
    final payment = Payment(
      id: 'P-${DateTime.now().millisecondsSinceEpoch}',
      billId: billId,
      userId: userId,
      paidAt: DateTime.now(),
      amount: bill.amount,
      method: method,
      txnRef: 'TXN${DateTime.now().millisecondsSinceEpoch}',
    );
    _payments.add(payment);

    _emitBills();
    return payment;
  }

  // ---------------- Feedback ----------------
  @override
  Stream<List<FeedbackEntry>> watchFeedbacksForUser(String userId) =>
      _fbCtrl.stream.map((list) => list.where((f) => f.userId == userId).toList());

  @override
  Future<FeedbackEntry?> getFeedbackForBill({
    required String billId,
    required String userId,
  }) async {
    try {
      return _feedbacks.firstWhere((f) => f.billId == billId && f.userId == userId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<FeedbackEntry> submitFeedback({
    required String billId,
    required String userId,
    required int rating,
    required String comment,
  }) async {
    // Optional: ensure user can only leave feedback for their own PAID bill
    final bill = _bills.firstWhere((b) => b.id == billId);
    if (bill.userId != userId) {
      throw Exception('You can only leave feedback for your own bill.');
    }
    if (bill.status != BillStatus.paid) {
      throw Exception('Bill must be paid before leaving feedback.');
    }
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be between 1 and 5.');
    }

    final existingIdx = _feedbacks.indexWhere((f) => f.billId == billId && f.userId == userId);
    final now = DateTime.now();

    if (existingIdx != -1) {
      final f = _feedbacks[existingIdx];
      f.rating = rating;
      f.comment = comment;
      f.createdAt = now;
      _emitFeedback();
      return f;
    } else {
      final entry = FeedbackEntry(
        id: 'F-${DateTime.now().millisecondsSinceEpoch}',
        billId: billId,
        userId: userId,
        rating: rating,
        comment: comment,
        createdAt: now,
      );
      _feedbacks.add(entry);
      _emitFeedback();
      return entry;
    }
  }
}
