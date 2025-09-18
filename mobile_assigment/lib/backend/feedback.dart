import 'package:cloud_firestore/cloud_firestore.dart';

class FeedbackModel {
  final String feedbackID;
  final String invoiceID;
  final int rating; // 1..5
  final String comment;
  final DateTime date;
  final String userId;
  final String? photoUrl; // optional uploaded photo

  FeedbackModel({
    required this.feedbackID,
    required this.invoiceID,
    required this.rating,
    required this.comment,
    required this.date,
    required this.userId,
    this.photoUrl,
  });

  Map<String, dynamic> toMap() => {
    'feedbackID': feedbackID,
    'invoiceID': invoiceID,
    'rating': rating,
    'comment': comment,
    'date': Timestamp.fromDate(date),
    'userId': userId,
    if (photoUrl != null) 'photoUrl': photoUrl,
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
      photoUrl: m['photoUrl'] as String?,
    );
  }
}

class FeedbackService {
  final _col = FirebaseFirestore.instance.collection('feedbacks');

  Future<FeedbackModel?> getMyFeedback(String invoiceID, String userId) async {
    final qs = await _col
        .where('invoiceID', isEqualTo: invoiceID)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    return FeedbackModel.fromDoc(qs.docs.first);
  }

  /// Create or update feedback for this invoice/user
  Future<void> upsertFeedback({
    required String invoiceID,
    required String userId,
    required int rating,
    required String comment,
    String? photoUrl,
  }) async {
    if (rating < 1 || rating > 5) {
      throw Exception('Rating must be 1–5');
    }

    final existing = await getMyFeedback(invoiceID, userId);
    final ref = existing == null ? _col.doc() : _col.doc(existing.feedbackID);

    final payload = {
      'feedbackID': ref.id,
      'invoiceID': invoiceID,
      'rating': rating,
      'comment': comment,
      'date': Timestamp.fromDate(DateTime.now()),
      'userId': userId,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };

    await ref.set(payload, SetOptions(merge: true));
  }
}
