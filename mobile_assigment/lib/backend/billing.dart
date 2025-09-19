import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceModel {
  final String invoiceID;
  final double amount;
  final String status; // 'paid' | 'pending'
  final DateTime date;
  final String bookingID;
  final String plateNumber;
  final String userId;

  InvoiceModel({
    required this.invoiceID,
    required this.amount,
    required this.status,
    required this.date,
    required this.bookingID,
    required this.plateNumber,
    required this.userId,
  });

  Map<String, dynamic> toMap() => {
        'invoiceID': invoiceID,
        'amount': amount,
        'status': status,
        'date': Timestamp.fromDate(date),
        'bookingID': bookingID,
        'plateNumber': plateNumber,
        'userId': userId,
      };

  factory InvoiceModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return InvoiceModel(
      invoiceID: m['invoiceID'] as String,
      amount: (m['amount'] as num).toDouble(),
      status: m['status'] as String,
      date: (m['date'] as Timestamp).toDate(),
      bookingID: m['bookingID'] as String,
      plateNumber: m['plateNumber'] as String,
      userId: m['userId'] as String,
    );
  }
}

class BillingService {
  final _col = FirebaseFirestore.instance.collection('invoices');

  Future<void> createInvoice({
    required String invoiceID,
    required String userId,
    required double amount,
    required String bookingID,
    required String plateNumber,
    DateTime? date,
  }) async {
    await _col.doc(invoiceID).set(InvoiceModel(
      invoiceID: invoiceID,
      amount: amount,
      status: 'pending',
      date: date ?? DateTime.now(),
      bookingID: bookingID,
      plateNumber: plateNumber,
      userId: userId,
    ).toMap());
  }

  Stream<List<InvoiceModel>> watchUserInvoicesSafe(String userId) {
    return _col
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((qs) {
          final list = qs.docs.map(InvoiceModel.fromDoc).toList();
          list.sort((a, b) => b.date.compareTo(a.date));
          return list;
        });
  }

  /// Only PAID invoices for current user (for the Feedback page)
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

  Future<InvoiceModel?> getInvoice(String id) async {
    final snap = await _col.doc(id).get();
    return snap.exists ? InvoiceModel.fromDoc(snap) : null;
  }

  Future<void> markPaid(String id) => _col.doc(id).update({'status': 'paid'});
}
