// lib/backend/billing.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// Invoice data model (matches Cloud Function output)
class InvoiceModel {
  final String invoiceID;
  final String userId;
  final String bookingID;
  final String plateNumber;
  final double amount;       // e.g. 120.0
  final String status;       // 'pending' | 'paid'
  final DateTime date;       // server time when created

  InvoiceModel({
    required this.invoiceID,
    required this.userId,
    required this.bookingID,
    required this.plateNumber,
    required this.amount,
    required this.status,
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'invoiceID': invoiceID,
        'userId': userId,
        'bookingID': bookingID,
        'plateNumber': plateNumber,
        'amount': amount,
        'status': status,
        'date': Timestamp.fromDate(date),
      };

  /// Robust factory that tolerates missing/typed fields
  factory InvoiceModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data() ?? const {};
    return InvoiceModel(
      invoiceID: (m['invoiceID'] ?? d.id) as String,
      userId: (m['userId'] ?? '') as String,
      bookingID: (m['bookingID'] ?? '') as String,
      plateNumber: (m['plateNumber'] ?? '') as String,
      amount: (m['amount'] is num) ? (m['amount'] as num).toDouble() : 0.0,
      status: (m['status'] ?? 'pending') as String,
      date: _asDate(m['date']),
    );
  }

  static DateTime _asDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.fromMillisecondsSinceEpoch(0);
  }
}

class BillingService {
  final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('invoices');

  /// Create an invoice manually (not required if using the Cloud Function,
  /// but handy for tests or admin tools).
  Future<void> createInvoice({
    required String invoiceID,
    required String userId,
    required String bookingID,
    required String plateNumber,
    double amount = 120.0,
    String status = 'pending',
    DateTime? date,
  }) async {
    final data = InvoiceModel(
      invoiceID: invoiceID,
      userId: userId,
      bookingID: bookingID,
      plateNumber: plateNumber,
      amount: amount,
      status: status,
      date: date ?? DateTime.now(),
    ).toMap();

    await _col.doc(invoiceID).set(data);
  }

  /// Get a single invoice by id
  Future<InvoiceModel?> getInvoice(String id) async {
    final snap = await _col.doc(id).get();
    return snap.exists ? InvoiceModel.fromDoc(snap) : null;
  }

  /// Mark invoice as paid
  Future<void> markPaid(String id) async {
    await _col.doc(id).update({'status': 'paid'});
  }

  /// Stream all invoices for a user (sorted in Dart so missing 'date' won't break)
  Stream<List<InvoiceModel>> watchUserInvoicesSafe(String userId) {
    return _col.where('userId', isEqualTo: userId).snapshots().map((qs) {
      final list = qs.docs.map(InvoiceModel.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }

  /// Stream only PAID invoices for a user (used by Feedback page)
  Stream<List<InvoiceModel>> watchPaidInvoicesSafe(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .where('status', isEqualTo: 'paid')
        .snapshots()
        .map((qs) {
      final list = qs.docs.map(InvoiceModel.fromDoc).toList();
      list.sort((a, b) => b.date.compareTo(a.date));
      return list;
    });
  }
}
