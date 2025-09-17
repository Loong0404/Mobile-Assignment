import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentModel {
  final String paymentID;
  final String invoiceID;
  final double amount;
  final String status; // 'paid' | 'pending'
  final DateTime paymentDate;
  final String paymentTime; // "HH:mm"
  final String userId;

  PaymentModel({
    required this.paymentID,
    required this.invoiceID,
    required this.amount,
    required this.status,
    required this.paymentDate,
    required this.paymentTime,
    required this.userId,
  });

  Map<String, dynamic> toMap() => {
        'paymentID': paymentID,
        'invoiceID': invoiceID,
        'amount': amount,
        'status': status,
        'paymentDate': Timestamp.fromDate(paymentDate),
        'paymentTime': paymentTime,
        'userId': userId,
      };

  factory PaymentModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return PaymentModel(
      paymentID: m['paymentID'] as String,
      invoiceID: m['invoiceID'] as String,
      amount: (m['amount'] as num).toDouble(),
      status: m['status'] as String,
      paymentDate: (m['paymentDate'] as Timestamp).toDate(),
      paymentTime: m['paymentTime'] as String,
      userId: m['userId'] as String,
    );
  }
}

class PaymentService {
  final _col = FirebaseFirestore.instance.collection('payments');

  Future<void> createPayment({
    required String invoiceID,
    required String userId,
    required double amount,
    required String paymentTime,
  }) async {
    final ref = _col.doc();
    await ref.set(PaymentModel(
      paymentID: ref.id,
      invoiceID: invoiceID,
      amount: amount,
      status: 'paid',
      paymentDate: DateTime.now(),
      paymentTime: paymentTime,
      userId: userId,
    ).toMap());
  }

  Stream<List<PaymentModel>> watchPayments(String invoiceID, String userId) {
    return _col
        .where('invoiceID', isEqualTo: invoiceID)
        .where('userId', isEqualTo: userId)
        .orderBy('paymentDate', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(PaymentModel.fromDoc).toList());
  }
}
