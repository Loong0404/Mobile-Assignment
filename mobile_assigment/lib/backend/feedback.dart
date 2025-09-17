import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackModel {
  final String feedbackID;
  final String invoiceID;
  final int rating;
  final String comment;
  final DateTime date;
  final String userId;

  FeedbackModel({
    required this.feedbackID,
    required this.invoiceID,
    required this.rating,
    required this.comment,
    required this.date,
    required this.userId,
  });

  Map<String, dynamic> toMap() => {
        'feedbackID': feedbackID,
        'invoiceID': invoiceID,
        'rating': rating,
        'comment': comment,
        'date': Timestamp.fromDate(date),
        'userId': userId,
      };

  factory FeedbackModel.fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data()!;
    return FeedbackModel(
      feedbackID: m['feedbackID'] as String,
      invoiceID: m['invoiceID'] as String,
      rating: (m['rating'] as num).toInt(),
      comment: m['comment'] as String,
      date: (m['date'] as Timestamp).toDate(),
      userId: m['userId'] as String,
    );
  }
}

class FeedbackService {
  final _col = FirebaseFirestore.instance.collection('feedbacks');

  Future<void> leaveFeedback({
    required String invoiceID,
    required String userId,
    required int rating,
    required String comment,
  }) async {
    if (rating < 1 || rating > 5) throw Exception('Rating must be 1–5');
    final ref = _col.doc();
    await ref.set(FeedbackModel(
      feedbackID: ref.id,
      invoiceID: invoiceID,
      rating: rating,
      comment: comment,
      date: DateTime.now(),
      userId: userId,
    ).toMap());
  }

  Stream<List<FeedbackModel>> watchFeedbacks(String invoiceID, String userId) {
    return _col
        .where('invoiceID', isEqualTo: invoiceID)
        .where('userId', isEqualTo: userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((qs) => qs.docs.map(FeedbackModel.fromDoc).toList());
  }
}
