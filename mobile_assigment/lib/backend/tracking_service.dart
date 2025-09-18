import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'tracking.dart';

class TrackingService {
  TrackingService._();
  static final TrackingService instance = TrackingService._();

  final _db = FirebaseFirestore.instance;
  final _auth = fb.FirebaseAuth.instance;
  final Map<String, bool> _bookingExistenceCache = {};

  CollectionReference get _trackingCol => _db.collection('Tracking');
  CollectionReference get _techCol => _db.collection('Technician');
  CollectionReference get _bookingCol => _db.collection('Booking');
  CollectionReference get _bookingsCol => _db.collection('Bookings');
  CollectionReference get _userCol => _db.collection('users');

  Stream<Technician?> streamTechnician(String technicianId) {
    return _techCol.doc(technicianId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Technician.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    });
  }

  Future<void> seedTechniciansIfEmpty() async {
    // Seed a catalog of technicians; if some already exist, upsert the rest
    final samples = <Technician>[
      Technician(
        id: 'T001',
        name: 'Alex Johnson',
        avatarUrl: 'https://i.pravatar.cc/150?img=12',
        yearsExperience: 8,
        skills: ['Engine Repair', 'Brake Systems', 'Diagnostics'],
      ),
      Technician(
        id: 'T002',
        name: 'Priya Sharma',
        avatarUrl: 'https://i.pravatar.cc/150?img=32',
        yearsExperience: 6,
        skills: ['Electrical Systems', 'Hybrid Vehicles', 'Diagnostics'],
      ),
      Technician(
        id: 'T003',
        name: 'Miguel Alvarez',
        avatarUrl: 'https://i.pravatar.cc/150?img=5',
        yearsExperience: 10,
        skills: ['Transmission', 'Suspension', 'Air Conditioning'],
      ),
      Technician(
        id: 'T004',
        name: 'Sarah Lee',
        avatarUrl: 'https://i.pravatar.cc/150?img=47',
        yearsExperience: 7,
        skills: ['Diagnostics', 'ABS/ESP', 'Wiring'],
      ),
      Technician(
        id: 'T005',
        name: 'Hassan Ali',
        avatarUrl: 'https://i.pravatar.cc/150?img=66',
        yearsExperience: 9,
        skills: ['Diesel Engines', 'Cooling Systems', 'Exhaust'],
      ),
      Technician(
        id: 'T006',
        name: 'Emily Carter',
        avatarUrl: 'https://i.pravatar.cc/150?img=21',
        yearsExperience: 5,
        skills: ['Battery Systems', 'EV Drivetrain', 'HV Safety'],
      ),
      Technician(
        id: 'T007',
        name: 'Kenji Tanaka',
        avatarUrl: 'https://i.pravatar.cc/150?img=14',
        yearsExperience: 11,
        skills: ['Engine Tuning', 'Turbo Systems', 'ECU Mapping'],
      ),
    ];
    for (final t in samples) {
      // Upsert without overwriting if identical
      await _techCol.doc(t.id).set(t.toMap());
    }
  }

  Future<Technician> getOrCreateTechnician(String? techId) async {
    if (techId != null && techId.isNotEmpty) {
      final doc = await _techCol.doc(techId).get();
      if (doc.exists) {
        return Technician.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }
    }
    // No technician specified or not found: pick a random one
    final tech = await _pickRandomTechnician();
    return tech;
  }

  Future<Technician> _pickRandomTechnician() async {
    var listSnap = await _techCol.limit(50).get();
    if (listSnap.docs.isEmpty) {
      await seedTechniciansIfEmpty();
      listSnap = await _techCol.limit(50).get();
    }
    if (listSnap.docs.isEmpty) {
      // Fallback to demo if seeding somehow failed
      final demo = Technician.demo();
      await _techCol.doc(demo.id).set(demo.toMap());
      return demo;
    }
    final rnd = DateTime.now().millisecondsSinceEpoch;
    final pick = listSnap.docs[rnd % listSnap.docs.length];
    return Technician.fromMap(pick.id, pick.data() as Map<String, dynamic>);
  }

  /// Initialize tracking documents for current user's bookings that miss tracking.
  /// Requires Booking documents to include fields: BookingID, UserID (Uxxx) or uid.
  Future<void> initTrackingsForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Resolve user's profile for UserID (Uxxx)
    final userDoc = await _userCol.doc(user.uid).get();
    final userId =
        (userDoc.data() as Map<String, dynamic>?)?['userId'] as String?;

    // Find bookings belonging to this user across common field names
    final queries = <Future<QuerySnapshot>>[];
    if (userId != null) {
      queries.add(_bookingCol.where('UserID', isEqualTo: userId).get());
      queries.add(_bookingCol.where('userId', isEqualTo: userId).get());
      queries.add(_bookingsCol.where('UserID', isEqualTo: userId).get());
      queries.add(_bookingsCol.where('userId', isEqualTo: userId).get());
    }
    queries.add(_bookingCol.where('uid', isEqualTo: user.uid).get());
    queries.add(_bookingsCol.where('uid', isEqualTo: user.uid).get());

    final results = await Future.wait(queries);
    final docs = <QueryDocumentSnapshot>{};
    for (final r in results) {
      docs.addAll(r.docs);
    }

    // If user has no bookings, do not initialize any tracking
    if (docs.isEmpty) return;

    for (final b in docs) {
      final data = b.data() as Map<String, dynamic>;
      // Require an explicit BookingID field; do not fallback to doc id
      final dynamic bookingIdRaw = data['BookingID'] ?? data['bookingId'];
      if (bookingIdRaw == null) {
        // Skip bookings without a proper BookingID
        continue;
      }
      final bookingId = bookingIdRaw.toString();
      if (bookingId.trim().isEmpty) {
        // Skip if BookingID is empty
        continue;
      }

      final existing = await _trackingCol
          .where('BookingID', isEqualTo: bookingId)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) continue; // already initialized

      final techId = data['TechnicianID'] as String?;
      final tech = await getOrCreateTechnician(techId);

      // Create demo content seeded for the booking and upload
      final demo = ServiceTracking.demo(bookingId: bookingId);
      final trackId = _trackingCol.doc().id;
      final created = ServiceTracking(
        id: trackId,
        bookingId: demo.bookingId,
        currentStatus: demo.currentStatus,
        updatedAt: demo.updatedAt,
        statusUpdates: demo.statusUpdates,
        technicianId: tech.id,
        technician: tech,
        userId: userId,
        uid: user.uid,
      );
      await _trackingCol.doc(trackId).set(created.toMap());
    }
  }

  Stream<List<ServiceTracking>> streamTrackingsForCurrentUser() async* {
    final user = _auth.currentUser;
    if (user == null) {
      yield [];
      return;
    }

    // Always filter by uid to avoid switching queries mid-stream
    Query query = _trackingCol.where('uid', isEqualTo: user.uid);
    // Avoid orderBy here to prevent composite index requirement and flicker
    yield* query.snapshots().asyncMap((s) async {
      final items = s.docs
          .map(
            (d) =>
                ServiceTracking.fromMap(d.id, d.data() as Map<String, dynamic>),
          )
          .toList();

      // Keep only trackings whose booking actually exists
      final result = <ServiceTracking>[];
      for (final t in items) {
        if (t.bookingId.isEmpty) continue;
        if (await _bookingExists(t.bookingId)) {
          result.add(t);
        }
      }
      // Sort by bookingId numeric part descending (e.g., B003 > B001)
      int parseBooking(String id) {
        final digits = RegExp(r"(\d+)").firstMatch(id)?.group(1) ?? '0';
        return int.tryParse(digits) ?? 0;
      }

      result.sort(
        (a, b) =>
            parseBooking(b.bookingId).compareTo(parseBooking(a.bookingId)),
      );
      return result;
    });
  }

  Future<ServiceTracking?> getTrackingByBooking(String bookingId) async {
    final snap = await _trackingCol
        .where('BookingID', isEqualTo: bookingId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final d = snap.docs.first;
    return ServiceTracking.fromMap(d.id, d.data() as Map<String, dynamic>);
  }

  Future<bool> _bookingExists(String bookingId) async {
    // Simple in-memory cache to avoid repeated calls
    final cached = _bookingExistenceCache[bookingId];
    if (cached != null) return cached;

    // 1) Check direct doc IDs in both collections
    final docA = await _bookingCol.doc(bookingId).get();
    if (docA.exists) {
      _bookingExistenceCache[bookingId] = true;
      return true;
    }
    final docB = await _bookingsCol.doc(bookingId).get();
    if (docB.exists) {
      _bookingExistenceCache[bookingId] = true;
      return true;
    }

    // 2) Check common field names
    final futures = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    final exists = futures.any((qs) => qs.docs.isNotEmpty);
    _bookingExistenceCache[bookingId] = exists;
    return exists;
  }
}

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final _db = FirebaseFirestore.instance;
  final _auth = fb.FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference get _chatCol => _db.collection('Chat');

  Stream<List<ChatMessage>> streamMessages(String trackId) {
    return _chatCol.where('TrackID', isEqualTo: trackId).snapshots().map((s) {
      final list = s.docs
          .map(
            (d) => ChatMessage.fromMap(d.id, d.data() as Map<String, dynamic>),
          )
          .toList();
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return list;
    });
  }

  Future<void> sendMessage({
    required String trackId,
    required String text,
    required String displayName,
    required String userId,
  }) async {
    final id = _chatCol.doc().id;
    await _chatCol.doc(id).set({
      'ChatID': id,
      'TrackID': trackId,
      'text': text,
      'date': FieldValue.serverTimestamp(),
      'UserID': userId,
      'senderName': displayName,
    });
  }

  Future<String> uploadImage(String trackId, String localPath) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to upload images.');
    }
    final uid = user.uid;
    // Use a path that matches current Storage rules: feedback_photos/{uid}/...
    final ref = _storage.ref().child(
      'feedback_photos/$uid/chat/$trackId/${DateTime.now().millisecondsSinceEpoch}_$uid.jpg',
    );
    await ref.putFile(
      File(localPath),
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return await ref.getDownloadURL();
  }

  Future<void> sendImage({
    required String trackId,
    required String imageUrl,
    required String displayName,
    required String userId,
  }) async {
    final id = _chatCol.doc().id;
    await _chatCol.doc(id).set({
      'ChatID': id,
      'TrackID': trackId,
      'text': '',
      'date': FieldValue.serverTimestamp(),
      'UserID': userId,
      'senderName': displayName,
      'images': [imageUrl],
    });
  }
}
