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
  final Map<String, String?> _plateCache = {};
  final Map<String, String?> _serviceTypeCache = {};
  StreamSubscription? _bookingWatchA;
  StreamSubscription? _bookingWatchB;
  StreamSubscription? _bookingWatchUserIdA;
  StreamSubscription? _bookingWatchUserIdB;
  StreamSubscription? _invoiceWatch;
  Timer? _debounceInit;
  Timer? _debounceInvoice;

  CollectionReference get _trackingCol => _db.collection('Tracking');
  CollectionReference get _techCol => _db.collection('Technician');
  CollectionReference get _bookingCol => _db.collection('Booking');
  CollectionReference get _bookingsCol => _db.collection('Bookings');
  CollectionReference get _userCol => _db.collection('users');
  CollectionReference get _serviceCol => _db.collection('Service');
  CollectionReference get _invoiceCol => _db.collection('invoices');

  Future<void> startLiveSync() async {
    final user = _auth.currentUser;
    if (user == null) return;
    // Avoid duplicating listeners
    await stopLiveSync();
    // Resolve user's profile for UserID (Uxxx)
    final userDoc = await _userCol.doc(user.uid).get();
    final userId =
        (userDoc.data() as Map<String, dynamic>?)?['userId'] as String?;

    void scheduleInit() {
      _debounceInit?.cancel();
      _debounceInit = Timer(const Duration(milliseconds: 200), () async {
        await initTrackingsForCurrentUser();
      });
    }

    void scheduleInvoice() {
      _debounceInvoice?.cancel();
      _debounceInvoice = Timer(const Duration(milliseconds: 200), () async {
        await applyInvoiceUpgradesForCurrentUser();
      });
    }

    _bookingWatchA = _bookingCol
        .where('uid', isEqualTo: user.uid)
        .snapshots()
        .listen((_) {
          scheduleInit();
        });
    if (userId != null) {
      _bookingWatchUserIdA = _bookingCol
          .where('UserID', isEqualTo: userId)
          .snapshots()
          .listen((_) {
            scheduleInit();
          });
    }
    _invoiceWatch = _invoiceCol
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .listen((_) => scheduleInvoice());
  }

  Future<void> stopLiveSync() async {
    await _bookingWatchA?.cancel();
    await _bookingWatchB?.cancel();
    await _bookingWatchUserIdA?.cancel();
    await _bookingWatchUserIdB?.cancel();
    await _invoiceWatch?.cancel();
    _bookingWatchA = null;
    _bookingWatchB = null;
    _bookingWatchUserIdA = null;
    _bookingWatchUserIdB = null;
    _invoiceWatch = null;
    _debounceInit?.cancel();
    _debounceInvoice?.cancel();
    _debounceInit = null;
    _debounceInvoice = null;
  }

  Stream<Technician?> streamTechnician(String technicianId) {
    return _techCol.doc(technicianId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Technician.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    });
  }

  /// When invoices change, upgrade any RFC trackings to Completed if there's a paid invoice.
  Future<void> applyInvoiceUpgradesForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final snap = await _trackingCol.where('uid', isEqualTo: user.uid).get();
    for (final d in snap.docs) {
      final data = d.data() as Map<String, dynamic>;
      final t = ServiceTracking.fromMap(d.id, data);
      if (t.currentStatus == TrackingBackend.readyForCollection) {
        final paidAt = await _getLatestPaidInvoiceDate(t.bookingId);
        if (paidAt != null) {
          await _upgradeTrackingToCompleted(t, paidAt);
        }
      }
    }
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

    // Find bookings belonging to this user (Booking collection only)
    final queries = <Future<QuerySnapshot>>[];
    if (userId != null) {
      queries.add(_bookingCol.where('UserID', isEqualTo: userId).get());
      queries.add(_bookingCol.where('userId', isEqualTo: userId).get());
    }
    queries.add(_bookingCol.where('uid', isEqualTo: user.uid).get());

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
      if (existing.docs.isNotEmpty) {
        // Backfill plateNumber into existing tracking if missing
        final trackDoc = existing.docs.first;
        final tData = trackDoc.data() as Map<String, dynamic>;
        // Sync status from Booking
        final bookingStatus =
            ((data['Status'] ?? data['status'])?.toString() ?? '')
                .toLowerCase()
                .trim();
        final currentTrackingStatus =
            (tData['status'] ?? tData['currentStatus'] ?? '').toString();
        final hasPlate =
            (tData['plateNumber'] ??
                tData['PlateNumber'] ??
                tData['plate'] ??
                tData['VehiclePlate']) !=
            null;
        // Backfill service info
        Map<String, dynamic> updates = {};
        if (bookingStatus == 'cancelled') {
          if ((tData['status']?.toString() ?? '') != 'Cancelled') {
            updates['status'] = 'Cancelled';
          }
          // Trim to Vehicle Received only for clarity
          if (tData['stages'] is Map) {
            final stages = Map<String, dynamic>.from(
              tData['stages'] as Map<String, dynamic>,
            );
            final key = TrackingBackend.vehicleReceived;
            final vr = Map<String, dynamic>.from(
              (stages[key] as Map?) ?? <String, dynamic>{},
            );
            final DateTime ts =
                _toDateTime(vr['startAt']) ??
                _toDateTime(vr['timestamp']) ??
                DateTime.now();
            final trimmed = <String, dynamic>{
              key: {
                'timestamp': ts,
                'notes': (vr['notes'] ?? 'Vehicle received at service center.')
                    .toString(),
                'imageUrls':
                    (vr['imageUrls'] as List?)?.cast<String>() ??
                    (vr['photoUrls'] as List?)?.cast<String>() ??
                    <String>[],
                'startAt': ts,
                'endAt': null,
              },
            };
            updates['stages'] = trimmed;
          }
        } else if (bookingStatus == 'expired') {
          if ((tData['status']?.toString() ?? '') != 'Expired') {
            updates['status'] = 'Expired';
          }
          // Trim to Vehicle Received only for clarity
          if (tData['stages'] is Map) {
            final stages = Map<String, dynamic>.from(
              tData['stages'] as Map<String, dynamic>,
            );
            final key = TrackingBackend.vehicleReceived;
            final vr = Map<String, dynamic>.from(
              (stages[key] as Map?) ?? <String, dynamic>{},
            );
            final DateTime ts =
                _toDateTime(vr['startAt']) ??
                _toDateTime(vr['timestamp']) ??
                DateTime.now();
            final trimmed = <String, dynamic>{
              key: {
                'timestamp': ts,
                'notes': (vr['notes'] ?? 'Vehicle received at service center.')
                    .toString(),
                'imageUrls':
                    (vr['imageUrls'] as List?)?.cast<String>() ??
                    (vr['photoUrls'] as List?)?.cast<String>() ??
                    <String>[],
                'startAt': ts,
                'endAt': null,
              },
            };
            updates['stages'] = trimmed;
          }
        } else if (bookingStatus == 'ready for collection') {
          // Upgrade tracking to RFC if booking says so (do not downgrade anything)
          final lowered = currentTrackingStatus.toLowerCase();
          final isTerminal =
              lowered == 'cancelled' ||
              lowered == 'expired' ||
              lowered == 'completed';
          if (!isTerminal &&
              lowered != TrackingBackend.readyForCollection.toLowerCase()) {
            updates['status'] = TrackingBackend.readyForCollection;
            // Rebuild stages up to RFC, align VR start with Booking.StartAt
            final demo = ServiceTracking.demo(
              bookingId: (tData['BookingID'] ?? tData['bookingId'] ?? '')
                  .toString(),
              status: TrackingBackend.readyForCollection,
            );
            final aligned = _alignVehicleReceivedStart(
              demo.statusUpdates,
              _toDateTime(data['StartAt']),
            );
            final flow = [
              TrackingBackend.vehicleReceived,
              TrackingBackend.initialDiagnosis,
              TrackingBackend.inInspection,
              TrackingBackend.partsAwaiting,
              TrackingBackend.inRepair,
              TrackingBackend.qualityCheck,
              TrackingBackend.finalTesting,
              TrackingBackend.readyForCollection,
            ];
            final pruned = <String, StatusUpdate>{};
            for (final s in flow) {
              final u = aligned[s];
              if (u != null) {
                pruned[s] = u;
              }
              if (s == TrackingBackend.readyForCollection) break;
            }
            final rfc = pruned[TrackingBackend.readyForCollection];
            if (rfc != null) {
              pruned[TrackingBackend.readyForCollection] = StatusUpdate(
                status: rfc.status,
                timestamp: rfc.timestamp,
                notes: rfc.notes,
                imageUrls: rfc.imageUrls,
                estimatedCompletionTime: rfc.estimatedCompletionTime,
                startAt: rfc.startAt ?? rfc.timestamp,
                endAt: null,
              );
            }
            final normalized = _normalizeStageTimes(pruned);
            updates['stages'] = normalized.map(
              (k, v) => MapEntry(k, v.toMap()),
            );
          }
        }
        final hasServiceId = (tData['ServiceID'] ?? tData['serviceId']) != null;
        String? serviceIdFromBooking =
            (data['ServiceID'] ?? data['serviceId']) as String?;
        if ((serviceIdFromBooking == null ||
                serviceIdFromBooking.trim().isEmpty) &&
            data['ServiceIDs'] is List) {
          final list = (data['ServiceIDs'] as List);
          if (list.isNotEmpty && list.first != null) {
            serviceIdFromBooking = list.first.toString();
          }
        }
        if (!hasServiceId &&
            serviceIdFromBooking != null &&
            serviceIdFromBooking.trim().isNotEmpty) {
          updates['ServiceID'] = serviceIdFromBooking;
          final stype = await _fetchServiceType(serviceIdFromBooking);
          if (stype != null && stype.trim().isNotEmpty) {
            updates['serviceType'] = stype;
          }
        } else if (hasServiceId &&
            (tData['serviceType'] == null ||
                (tData['serviceType'] as String).trim().isEmpty)) {
          final sid = (tData['ServiceID'] ?? tData['serviceId']) as String?;
          if (sid != null) {
            final stype = await _fetchServiceType(sid);
            if (stype != null && stype.trim().isNotEmpty) {
              updates['serviceType'] = stype;
            }
          }
        }
        // Backfill arrays ServiceIDs/ServiceTypes if missing
        final bool hasServiceIdsArray =
            tData['ServiceIDs'] is List &&
            (tData['ServiceIDs'] as List).isNotEmpty;
        final bool hasServiceTypesArray =
            tData['ServiceTypes'] is List &&
            (tData['ServiceTypes'] as List).isNotEmpty;
        if (!hasServiceIdsArray || !hasServiceTypesArray) {
          final ids = _extractServiceIds(data);
          if (ids.isNotEmpty) {
            final types = await _fetchServiceTypesForIds(ids);
            if (!hasServiceIdsArray) updates['ServiceIDs'] = ids;
            if (!hasServiceTypesArray && types.isNotEmpty) {
              updates['ServiceTypes'] = types;
            }
          }
        }
        if (!hasPlate) {
          // Always derive by bookingId to avoid mismatches
          final fetched = await fetchPlateNumberForBooking(bookingId);
          if (fetched != null && fetched.trim().isNotEmpty) {
            updates['plateNumber'] = fetched;
          }
        }
        // Defensive trim: if tracking shows Vehicle Received as current status
        // but contains other stages (and booking status is unknown), keep only VR.
        if (updates.isEmpty) {
          final currentStatusStr =
              (tData['status'] ?? tData['currentStatus'] ?? '').toString();
          final isVR =
              currentStatusStr.toLowerCase() ==
              TrackingBackend.vehicleReceived.toLowerCase();
          if (isVR && tData['stages'] is Map) {
            final stages = Map<String, dynamic>.from(
              tData['stages'] as Map<String, dynamic>,
            );
            final key = TrackingBackend.vehicleReceived;
            final vr = Map<String, dynamic>.from(
              (stages[key] as Map?) ?? <String, dynamic>{},
            );
            // Prefer Booking.StartAt if available
            final DateTime? startAt = _toDateTime(data['StartAt']);
            final DateTime ts =
                startAt ??
                _toDateTime(vr['startAt']) ??
                _toDateTime(vr['timestamp']) ??
                DateTime.now();
            final trimmed = <String, dynamic>{
              key: {
                'timestamp': ts,
                'notes': (vr['notes'] ?? 'Vehicle received at service center.')
                    .toString(),
                'imageUrls':
                    (vr['imageUrls'] as List?)?.cast<String>() ??
                    (vr['photoUrls'] as List?)?.cast<String>() ??
                    <String>[],
                'startAt': ts,
                'endAt': null,
              },
            };
            updates['stages'] = trimmed;
          }
        }
        if (updates.isNotEmpty) {
          await _trackingCol.doc(trackDoc.id).update(updates);
        }
        continue; // already initialized otherwise
      }

      final techId = data['TechnicianID'] as String?;
      final bookingStatus =
          ((data['Status'] ?? data['status'])?.toString() ?? '')
              .toLowerCase()
              .trim();
      // First-time initialization must be based on Booking status 'received' only
      if (bookingStatus != 'received') {
        // Do not create tracking for other statuses (pending, RFC, cancelled, expired)
        continue;
      }
      // Read all serviceIds from Booking and resolve their types
      final List<String> serviceIds = _extractServiceIds(data);
      String? serviceId = serviceIds.isNotEmpty ? serviceIds.first : null;
      final List<String> serviceTypes = serviceIds.isNotEmpty
          ? await _fetchServiceTypesForIds(serviceIds)
          : <String>[];
      String? serviceType = (serviceId != null && serviceIds.isNotEmpty)
          ? (serviceTypes.length >= 1
                ? serviceTypes[0]
                : await _fetchServiceType(serviceId))
          : null;
      final tech = await getOrCreateTechnician(techId);

      // Create demo content seeded for the booking and upload
      final demo = ServiceTracking.demo(bookingId: bookingId);
      final trackId = _trackingCol.doc().id;
      // Strictly derive plate by bookingId
      final plate = await fetchPlateNumberForBooking(bookingId);
      // Enrich stage notes with selected services (esp. Parts Awaiting/In Repair)
      final enrichedStages = _enrichStageNotesMap(
        demo.statusUpdates,
        serviceIds,
        serviceTypes,
      );
      // Align Vehicle Received start with Booking.StartAt when provided
      final alignedStages = _alignVehicleReceivedStart(
        enrichedStages,
        _toDateTime(data['StartAt']),
      );
      // First-time initialization: always Vehicle Received only
      final String initialStatus = TrackingBackend.vehicleReceived;
      final Map<String, StatusUpdate> initialStages = _onlyVehicleReceivedStage(
        alignedStages,
        _toDateTime(data['StartAt']),
      );

      final created = ServiceTracking(
        id: trackId,
        bookingId: demo.bookingId,
        plateNumber: plate,
        serviceId: serviceId,
        serviceType: serviceType,
        serviceIds: serviceIds.isNotEmpty ? serviceIds : null,
        serviceTypes: serviceTypes.isNotEmpty ? serviceTypes : null,
        currentStatus: initialStatus,
        updatedAt: DateTime.now(),
        statusUpdates: initialStages,
        technicianId: tech.id,
        technician: tech,
        userId: userId,
        uid: user.uid,
      );
      await _trackingCol.doc(trackId).set(created.toMap());
    }
  }

  // Convert various dynamic representations to DateTime
  DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    if (v is Timestamp) return v.toDate();
    return DateTime.tryParse(v.toString());
  }

  // Align the 'Vehicle Received' stage start/timestamp
  Map<String, StatusUpdate> _alignVehicleReceivedStart(
    Map<String, StatusUpdate> original,
    DateTime? startAt,
  ) {
    if (startAt == null) return original;
    final out = Map<String, StatusUpdate>.from(original);
    final key = TrackingBackend.vehicleReceived;
    final u = out[key];
    if (u != null) {
      // Ensure endAt is not before startAt
      DateTime? adjustedEnd = u.endAt;
      if (adjustedEnd != null && adjustedEnd.isBefore(startAt)) {
        adjustedEnd = null;
      }
      out[key] = StatusUpdate(
        status: u.status,
        timestamp: startAt,
        notes: u.notes,
        imageUrls: u.imageUrls,
        estimatedCompletionTime: u.estimatedCompletionTime,
        startAt: startAt,
        endAt: adjustedEnd,
      );
    }
    return out;
  }

  // Ensure for every stage that endAt is not before startAt
  Map<String, StatusUpdate> _normalizeStageTimes(
    Map<String, StatusUpdate> stages,
  ) {
    final out = <String, StatusUpdate>{};
    stages.forEach((key, u) {
      DateTime? start = u.startAt;
      DateTime? end = u.endAt;
      if (start != null && end != null && end.isBefore(start)) {
        end = null;
      }
      out[key] = StatusUpdate(
        status: u.status,
        timestamp: u.timestamp,
        notes: u.notes,
        imageUrls: u.imageUrls,
        estimatedCompletionTime: u.estimatedCompletionTime,
        startAt: start,
        endAt: end,
      );
    });
    return out;
  }

  // Same normalization but for a dynamic map that mirrors toMap() output
  Map<String, dynamic> _normalizeDynamicStageTimes(
    Map<String, dynamic> stages,
  ) {
    final out = <String, dynamic>{};
    stages.forEach((key, value) {
      if (value is Map) {
        final m = Map<String, dynamic>.from(value as Map);
        final start = _toDateTime(m['startAt']);
        final end = _toDateTime(m['endAt']);
        if (start != null && end != null && end.isBefore(start)) {
          m['endAt'] = null;
        }
        out[key] = m;
      } else {
        out[key] = value;
      }
    });
    return out;
  }

  // Keep only the 'Vehicle Received' stage with a valid start time
  Map<String, StatusUpdate> _onlyVehicleReceivedStage(
    Map<String, StatusUpdate> stages,
    DateTime? startAt,
  ) {
    final key = TrackingBackend.vehicleReceived;
    final u = stages[key];
    final begin = startAt ?? u?.startAt ?? DateTime.now();
    final notes = u?.notes ?? 'Vehicle received at service center.';
    final images = u?.imageUrls ?? const <String>[];
    final est = u?.estimatedCompletionTime;
    return {
      key: StatusUpdate(
        status: key,
        timestamp: begin,
        notes: notes,
        imageUrls: images,
        estimatedCompletionTime: est,
        startAt: begin,
        endAt: null,
      ),
    };
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

      // Keep only trackings whose booking actually exists and backfill missing plates strictly by bookingId
      final result = <ServiceTracking>[];
      for (final t in items) {
        if (t.bookingId.isEmpty) continue;
        if (await _bookingExists(t.bookingId)) {
          // Hide any tracking if the booking is still pending (defensive)
          final status = await _fetchBookingStatus(t.bookingId);
          if (status == 'pending') {
            continue;
          }
          ServiceTracking toAdd = t;
          final hasPlate =
              t.plateNumber != null && t.plateNumber!.trim().isNotEmpty;
          if (!hasPlate) {
            final p = await fetchPlateNumberForBooking(t.bookingId);
            if (p != null && p.trim().isNotEmpty) {
              // Persist to Firestore for future loads
              try {
                await _trackingCol.doc(t.id).update({'plateNumber': p});
              } catch (_) {
                // ignore failures; still update in-memory object
              }
              // Update the in-memory object so UI shows immediately
              toAdd = ServiceTracking(
                id: t.id,
                bookingId: t.bookingId,
                plateNumber: p,
                serviceId: t.serviceId,
                serviceType: t.serviceType,
                currentStatus: t.currentStatus,
                updatedAt: t.updatedAt,
                statusUpdates: t.statusUpdates,
                technicianId: t.technicianId,
                technician: t.technician,
                userId: t.userId,
                uid: t.uid,
              );
            }
          }

          // Backfill missing service info from Booking+Service collections
          if ((toAdd.serviceId == null || toAdd.serviceId!.trim().isEmpty) ||
              (toAdd.serviceType == null ||
                  toAdd.serviceType!.trim().isEmpty)) {
            final pair = await _fetchServiceInfoForBooking(toAdd.bookingId);
            final sid = pair.$1;
            final stype = pair.$2;
            final update = <String, dynamic>{};
            String? useSid = toAdd.serviceId;
            String? useSType = toAdd.serviceType;
            if (sid != null &&
                sid.trim().isNotEmpty &&
                (toAdd.serviceId == null || toAdd.serviceId!.trim().isEmpty)) {
              update['ServiceID'] = sid;
              useSid = sid;
            }
            if (stype != null &&
                stype.trim().isNotEmpty &&
                (toAdd.serviceType == null ||
                    toAdd.serviceType!.trim().isEmpty)) {
              update['serviceType'] = stype;
              useSType = stype;
            }
            if (update.isNotEmpty) {
              try {
                await _trackingCol.doc(toAdd.id).update(update);
              } catch (_) {}
              toAdd = ServiceTracking(
                id: toAdd.id,
                bookingId: toAdd.bookingId,
                plateNumber: toAdd.plateNumber,
                serviceId: useSid,
                serviceType: useSType,
                currentStatus: toAdd.currentStatus,
                updatedAt: toAdd.updatedAt,
                statusUpdates: toAdd.statusUpdates,
                technicianId: toAdd.technicianId,
                technician: toAdd.technician,
                userId: toAdd.userId,
                uid: toAdd.uid,
              );
            }
          }
          // Backfill arrays ServiceIDs/ServiceTypes if missing or incomplete
          final needsIds =
              (toAdd.serviceIds == null || toAdd.serviceIds!.isEmpty);
          final needsTypes =
              (toAdd.serviceTypes == null ||
              (toAdd.serviceIds != null &&
                  toAdd.serviceTypes!.length < toAdd.serviceIds!.length));
          if (needsIds || needsTypes) {
            final listPair = await _fetchServicesListForBooking(
              toAdd.bookingId,
            );
            final ids = listPair.$1;
            final types = listPair.$2;
            if (ids.isNotEmpty) {
              final update = <String, dynamic>{};
              if (needsIds) update['ServiceIDs'] = ids;
              if (needsTypes && types.isNotEmpty)
                update['ServiceTypes'] = types;
              if (update.isNotEmpty) {
                try {
                  await _trackingCol.doc(toAdd.id).update(update);
                } catch (_) {}
                toAdd = ServiceTracking(
                  id: toAdd.id,
                  bookingId: toAdd.bookingId,
                  plateNumber: toAdd.plateNumber,
                  serviceId: toAdd.serviceId,
                  serviceType: toAdd.serviceType,
                  serviceIds: ids,
                  serviceTypes: types,
                  currentStatus: toAdd.currentStatus,
                  updatedAt: toAdd.updatedAt,
                  statusUpdates: toAdd.statusUpdates,
                  technicianId: toAdd.technicianId,
                  technician: toAdd.technician,
                  userId: toAdd.userId,
                  uid: toAdd.uid,
                );
              }
            }
          }
          // Ensure stages match current status rules
          final lowered = toAdd.currentStatus.toLowerCase();
          if (lowered == 'cancelled' || lowered == 'expired') {
            if (toAdd.statusUpdates.isNotEmpty) {
              try {
                await _trackingCol.doc(toAdd.id).update({'stages': {}});
              } catch (_) {}
              toAdd = ServiceTracking(
                id: toAdd.id,
                bookingId: toAdd.bookingId,
                plateNumber: toAdd.plateNumber,
                serviceId: toAdd.serviceId,
                serviceType: toAdd.serviceType,
                serviceIds: toAdd.serviceIds,
                serviceTypes: toAdd.serviceTypes,
                currentStatus: toAdd.currentStatus,
                updatedAt: toAdd.updatedAt,
                statusUpdates: const {},
                technicianId: toAdd.technicianId,
                technician: toAdd.technician,
                userId: toAdd.userId,
                uid: toAdd.uid,
              );
            }
          } else {
            // Build required stages up to current status if missing/misaligned
            final serviceFlow = [
              TrackingBackend.vehicleReceived,
              TrackingBackend.initialDiagnosis,
              TrackingBackend.inInspection,
              TrackingBackend.partsAwaiting,
              TrackingBackend.inRepair,
              TrackingBackend.qualityCheck,
              TrackingBackend.finalTesting,
              TrackingBackend.readyForCollection,
            ];
            final idx = serviceFlow.indexOf(toAdd.currentStatus);
            if (idx >= 0) {
              bool needsRebuild = false;
              // missing any required stage?
              for (int i = 0; i <= idx; i++) {
                if (!toAdd.statusUpdates.containsKey(serviceFlow[i])) {
                  needsRebuild = true;
                  break;
                }
              }
              // has extra future stages?
              if (!needsRebuild) {
                for (final key in toAdd.statusUpdates.keys) {
                  final kidx = serviceFlow.indexOf(key);
                  if (kidx > idx && kidx != -1) {
                    needsRebuild = true;
                    break;
                  }
                }
              }
              // Ready for Collection should not be completed
              if (!needsRebuild &&
                  toAdd.currentStatus == TrackingBackend.readyForCollection) {
                final rfc =
                    toAdd.statusUpdates[TrackingBackend.readyForCollection];
                if (rfc != null && rfc.endAt != null) {
                  needsRebuild = true;
                }
              }

              if (needsRebuild) {
                final demo = ServiceTracking.demo(
                  bookingId: toAdd.bookingId,
                  status: toAdd.currentStatus,
                );
                final startAt = await _fetchStartAtForBooking(toAdd.bookingId);
                Map<String, StatusUpdate> rebased = _alignVehicleReceivedStart(
                  demo.statusUpdates,
                  startAt,
                );
                // keep only up to current status
                final pruned = <String, StatusUpdate>{};
                for (int i = 0; i <= idx; i++) {
                  final s = serviceFlow[i];
                  final u = rebased[s];
                  if (u != null) pruned[s] = u;
                }
                // ensure RFC is active (no endAt)
                if (toAdd.currentStatus == TrackingBackend.readyForCollection) {
                  final u = pruned[TrackingBackend.readyForCollection];
                  if (u != null) {
                    pruned[TrackingBackend.readyForCollection] = StatusUpdate(
                      status: u.status,
                      timestamp: u.timestamp,
                      notes: u.notes,
                      imageUrls: u.imageUrls,
                      estimatedCompletionTime: u.estimatedCompletionTime,
                      startAt: u.startAt ?? u.timestamp,
                      endAt: null,
                    );
                  }
                }
                // Normalize times before persisting
                final normalized = _normalizeStageTimes(pruned);
                try {
                  await _trackingCol.doc(toAdd.id).update({
                    'stages': normalized.map((k, v) => MapEntry(k, v.toMap())),
                  });
                } catch (_) {}
                toAdd = ServiceTracking(
                  id: toAdd.id,
                  bookingId: toAdd.bookingId,
                  plateNumber: toAdd.plateNumber,
                  serviceId: toAdd.serviceId,
                  serviceType: toAdd.serviceType,
                  serviceIds: toAdd.serviceIds,
                  serviceTypes: toAdd.serviceTypes,
                  currentStatus: toAdd.currentStatus,
                  updatedAt: DateTime.now(),
                  statusUpdates: normalized,
                  technicianId: toAdd.technicianId,
                  technician: toAdd.technician,
                  userId: toAdd.userId,
                  uid: toAdd.uid,
                );
              }
            }

            // Auto-complete: If RFC and there's a PAID invoice for this booking, mark Completed
            if (toAdd.currentStatus == TrackingBackend.readyForCollection) {
              final paidAt = await _getLatestPaidInvoiceDate(toAdd.bookingId);
              if (paidAt != null) {
                final completed = await _upgradeTrackingToCompleted(
                  toAdd,
                  paidAt,
                );
                toAdd = completed ?? toAdd;
              }
            }
          }
          result.add(toAdd);
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

  // Find latest PAID invoice date for a booking; returns null if none
  Future<DateTime?> _getLatestPaidInvoiceDate(String bookingId) async {
    try {
      final qs = await _invoiceCol
          .where('bookingID', isEqualTo: bookingId)
          .where('status', isEqualTo: 'paid')
          .get();
      if (qs.docs.isEmpty) return null;
      DateTime? latest;
      for (final d in qs.docs) {
        final data = d.data() as Map<String, dynamic>;
        final dt = _toDateTime(data['date']);
        if (dt != null) {
          if (latest == null || dt.isAfter(latest)) latest = dt;
        }
      }
      return latest ?? DateTime.now();
    } catch (_) {
      return null;
    }
  }

  // Upgrade a tracking record to Completed and set RFC endAt to payment time
  Future<ServiceTracking?> _upgradeTrackingToCompleted(
    ServiceTracking t,
    DateTime paidAt,
  ) async {
    try {
      // Build updated stages: ensure RFC endAt reflects payment time
      final stages = Map<String, StatusUpdate>.from(t.statusUpdates);
      final rfcKey = TrackingBackend.readyForCollection;
      final rfc = stages[rfcKey];
      StatusUpdate? updatedRfc;
      if (rfc != null) {
        DateTime start = rfc.startAt ?? rfc.timestamp;
        DateTime end = paidAt.isBefore(start) ? start : paidAt;
        updatedRfc = StatusUpdate(
          status: rfc.status,
          timestamp: rfc.timestamp,
          notes: rfc.notes,
          imageUrls: rfc.imageUrls,
          estimatedCompletionTime: rfc.estimatedCompletionTime,
          startAt: start,
          endAt: end,
        );
      }
      if (updatedRfc != null) {
        stages[rfcKey] = updatedRfc;
      }
      final normalized = _normalizeStageTimes(stages);

      await _trackingCol.doc(t.id).update({
        'status': 'Completed',
        'stages': normalized.map((k, v) => MapEntry(k, v.toMap())),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return ServiceTracking(
        id: t.id,
        bookingId: t.bookingId,
        plateNumber: t.plateNumber,
        serviceId: t.serviceId,
        serviceType: t.serviceType,
        serviceIds: t.serviceIds,
        serviceTypes: t.serviceTypes,
        currentStatus: 'Completed',
        updatedAt: DateTime.now(),
        statusUpdates: normalized,
        technicianId: t.technicianId,
        technician: t.technician,
        userId: t.userId,
        uid: t.uid,
      );
    } catch (_) {
      return null;
    }
  }

  // Get Booking.StartAt if available
  Future<DateTime?> _fetchStartAtForBooking(String bookingId) async {
    final byId = await _bookingCol.doc(bookingId).get();
    if (byId.exists) {
      final d = byId.data() as Map<String, dynamic>;
      final v = d['StartAt'];
      final dt = _toDateTime(v);
      if (dt != null) return dt;
    }
    final byIdB = await _bookingsCol.doc(bookingId).get();
    if (byIdB.exists) {
      final d = byIdB.data() as Map<String, dynamic>;
      final v = d['StartAt'];
      final dt = _toDateTime(v);
      if (dt != null) return dt;
    }
    // Try by BookingID field
    final queries = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    for (final q in queries) {
      if (q.docs.isNotEmpty) {
        final d = q.docs.first.data() as Map<String, dynamic>;
        final v = d['StartAt'];
        final dt = _toDateTime(v);
        if (dt != null) return dt;
      }
    }
    return null;
  }

  // Fetch service type by serviceId with cache
  Future<String?> _fetchServiceType(String serviceId) async {
    if (_serviceTypeCache.containsKey(serviceId)) {
      return _serviceTypeCache[serviceId];
    }
    final doc = await _serviceCol.doc(serviceId).get();
    if (!doc.exists) {
      _serviceTypeCache[serviceId] = null;
      return null;
    }
    final data = doc.data() as Map<String, dynamic>;
    final type = (data['serviceType'] ?? data['ServiceType']) as String?;
    _serviceTypeCache[serviceId] = type;
    return type;
  }

  // Determine serviceId from Booking and serviceType from Service
  Future<(String?, String?)> _fetchServiceInfoForBooking(
    String bookingId,
  ) async {
    // 1) Try Booking doc by id
    for (final col in [_bookingCol, _bookingsCol]) {
      final d = await col.doc(bookingId).get();
      if (d.exists) {
        final map = d.data() as Map<String, dynamic>;
        String? sid = (map['ServiceID'] ?? map['serviceId']) as String?;
        if ((sid == null || sid.trim().isEmpty) && map['ServiceIDs'] is List) {
          final list = (map['ServiceIDs'] as List);
          if (list.isNotEmpty && list.first != null)
            sid = list.first.toString();
        }
        final stype = sid == null ? null : await _fetchServiceType(sid);
        return (sid, stype);
      }
    }
    // 2) Try by BookingID field
    final queries = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    for (final q in queries) {
      if (q.docs.isNotEmpty) {
        final map = q.docs.first.data() as Map<String, dynamic>;
        String? sid = (map['ServiceID'] ?? map['serviceId']) as String?;
        if ((sid == null || sid.trim().isEmpty) && map['ServiceIDs'] is List) {
          final list = (map['ServiceIDs'] as List);
          if (list.isNotEmpty && list.first != null)
            sid = list.first.toString();
        }
        final stype = sid == null ? null : await _fetchServiceType(sid);
        return (sid, stype);
      }
    }
    return (null, null);
  }

  // Read all service IDs from a booking map. Accepts either `ServiceID` (single)
  // and/or `ServiceIDs` (list). Returns a de-duplicated ordered list of strings.
  List<String> _extractServiceIds(Map<String, dynamic> bookingMap) {
    final ids = <String>[];
    final single =
        (bookingMap['ServiceID'] ?? bookingMap['serviceId']) as String?;
    if (single != null && single.trim().isNotEmpty) ids.add(single.trim());
    final list = bookingMap['ServiceIDs'];
    if (list is List) {
      for (final v in list) {
        final s = v?.toString();
        if (s != null && s.trim().isNotEmpty && !ids.contains(s.trim())) {
          ids.add(s.trim());
        }
      }
    }
    return ids;
  }

  // Fetch service types for a list of ids preserving order. Missing entries yield '' placeholders.
  Future<List<String>> _fetchServiceTypesForIds(List<String> ids) async {
    final types = await Future.wait(
      ids.map((id) async {
        final t = await _fetchServiceType(id);
        return t ?? '';
      }),
    );
    return types;
  }

  // Fetch full services list (ids and types) for a booking id from Booking/Bookings collections.
  Future<(List<String>, List<String>)> _fetchServicesListForBooking(
    String bookingId,
  ) async {
    // Try by document id
    for (final col in [_bookingCol, _bookingsCol]) {
      final d = await col.doc(bookingId).get();
      if (d.exists) {
        final map = d.data() as Map<String, dynamic>;
        final ids = _extractServiceIds(map);
        final types = ids.isNotEmpty
            ? await _fetchServiceTypesForIds(ids)
            : <String>[];
        return (ids, types);
      }
    }
    // Try by BookingID field
    final queries = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    for (final q in queries) {
      if (q.docs.isNotEmpty) {
        final map = q.docs.first.data() as Map<String, dynamic>;
        final ids = _extractServiceIds(map);
        final types = ids.isNotEmpty
            ? await _fetchServiceTypesForIds(ids)
            : <String>[];
        return (ids, types);
      }
    }
    return (<String>[], <String>[]);
  }

  // Enrich stage notes with selected services: append short, user-friendly lines
  Map<String, StatusUpdate> _enrichStageNotesMap(
    Map<String, StatusUpdate> original,
    List<String> serviceIds,
    List<String> serviceTypes,
  ) {
    if (serviceIds.isEmpty) return original;
    final Map<String, StatusUpdate> out = {};
    for (final entry in original.entries) {
      final s = entry.key;
      final u = entry.value;
      String notes = u.notes;
      if (s == TrackingBackend.partsAwaiting) {
        final lines = <String>['', 'Items queued per selected services:'];
        for (int i = 0; i < serviceIds.length; i++) {
          final id = serviceIds[i];
          final type =
              (i < serviceTypes.length && serviceTypes[i].trim().isNotEmpty)
              ? serviceTypes[i]
              : '';
          final label = [id, if (type.isNotEmpty) type].join(' • ');
          lines.add('- Parts ordered for $label');
        }
        notes = [notes, ...lines].join('\n');
      } else if (s == TrackingBackend.inRepair) {
        final lines = <String>['', 'Currently working on:'];
        for (int i = 0; i < serviceIds.length; i++) {
          final id = serviceIds[i];
          final type =
              (i < serviceTypes.length && serviceTypes[i].trim().isNotEmpty)
              ? serviceTypes[i]
              : '';
          final label = [id, if (type.isNotEmpty) type].join(' • ');
          lines.add('- $label');
        }
        notes = [notes, ...lines].join('\n');
      }
      out[s] = StatusUpdate(
        status: u.status,
        timestamp: u.timestamp,
        notes: notes,
        imageUrls: u.imageUrls,
        estimatedCompletionTime: u.estimatedCompletionTime,
        startAt: u.startAt,
        endAt: u.endAt,
      );
    }
    return out;
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

  /// Fetch the car plate number associated with a booking.
  /// Tries common locations and field names across `Booking` and `Bookings` collections.
  Future<String?> fetchPlateNumberForBooking(String bookingId) async {
    // Cache to reduce reads per list rebuild
    if (_plateCache.containsKey(bookingId)) return _plateCache[bookingId];

    // 1) Try document IDs directly (Booking and Bookings)
    final byIdA = await _bookingCol.doc(bookingId).get();
    if (byIdA.exists) {
      final d = byIdA.data() as Map<String, dynamic>;
      final plate =
          (d['plateNumber'] ??
                  d['PlateNumber'] ??
                  d['plate'] ??
                  d['VehiclePlate'])
              as String?;
      if (plate != null && plate.toString().trim().isNotEmpty) {
        _plateCache[bookingId] = plate;
        return plate;
      }
    }
    final byIdB = await _bookingsCol.doc(bookingId).get();
    if (byIdB.exists) {
      final d = byIdB.data() as Map<String, dynamic>;
      final plate =
          (d['plateNumber'] ??
                  d['PlateNumber'] ??
                  d['plate'] ??
                  d['VehiclePlate'])
              as String?;
      if (plate != null && plate.toString().trim().isNotEmpty) {
        _plateCache[bookingId] = plate;
        return plate;
      }
    }

    // 2) Try matching by BookingID field (BookingID/bookingId)
    final queries = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    for (final q in queries) {
      if (q.docs.isNotEmpty) {
        final d = q.docs.first.data() as Map<String, dynamic>;
        final plate =
            (d['plateNumber'] ??
                    d['PlateNumber'] ??
                    d['plate'] ??
                    d['VehiclePlate'])
                as String?;
        if (plate != null && plate.toString().trim().isNotEmpty) {
          _plateCache[bookingId] = plate;
          return plate;
        }
      }
    }

    _plateCache[bookingId] = null;
    return null;
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

  // Fetch normalized booking status for a booking id from Booking/Bookings collections
  Future<String?> _fetchBookingStatus(String bookingId) async {
    // Direct doc id first
    for (final col in [_bookingCol, _bookingsCol]) {
      final d = await col.doc(bookingId).get();
      if (d.exists) {
        final m = d.data() as Map<String, dynamic>;
        final s = (m['Status'] ?? m['status'])?.toString();
        if (s != null) return s.toLowerCase().trim();
      }
    }
    // By BookingID field
    final queries = await Future.wait([
      _bookingCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('BookingID', isEqualTo: bookingId).limit(1).get(),
      _bookingsCol.where('bookingId', isEqualTo: bookingId).limit(1).get(),
    ]);
    for (final q in queries) {
      if (q.docs.isNotEmpty) {
        final m = q.docs.first.data() as Map<String, dynamic>;
        final s = (m['Status'] ?? m['status'])?.toString();
        if (s != null) return s.toLowerCase().trim();
      }
    }
    return null;
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
