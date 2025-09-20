import 'package:flutter/material.dart';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class TrackingBackend {
  // Singleton instance
  static TrackingBackend instance = TrackingBackend._();

  TrackingBackend._();

  // Service status types
  static const String vehicleReceived = 'Vehicle Received';
  static const String initialDiagnosis = 'Initial Diagnosis';
  static const String inInspection = 'In Inspection';
  static const String partsAwaiting = 'Parts Awaiting';
  static const String inRepair = 'In Repair';
  static const String qualityCheck = 'Quality Check';
  static const String finalTesting = 'Final Testing';
  static const String readyForCollection = 'Ready for Collection';

  // List of all statuses in order
  static List<String> get allStatuses => [
    readyForCollection,
    vehicleReceived,
    initialDiagnosis,
    inInspection,
    partsAwaiting,
    inRepair,
    qualityCheck,
    finalTesting,
  ];

  // Get status icon
  static IconData getStatusIcon(String status) {
    switch (status) {
      case vehicleReceived:
        return Icons.directions_car;
      case initialDiagnosis:
        return Icons.assessment;
      case inInspection:
        return Icons.search;
      case partsAwaiting:
        return Icons.inventory;
      case inRepair:
        return Icons.build;
      case qualityCheck:
        return Icons.fact_check;
      case finalTesting:
        return Icons.speed;
      case readyForCollection:
        return Icons.check_circle;
      default:
        return Icons.help_outline;
    }
  }

  // Get status color
  static Color getStatusColor(String status) {
    switch (status) {
      case vehicleReceived:
        return Colors.purple;
      case initialDiagnosis:
        return Colors.indigo;
      case inInspection:
        return Colors.blue;
      case partsAwaiting:
        return Colors.orange;
      case inRepair:
        return Colors.amber;
      case qualityCheck:
        return Colors.cyan;
      case finalTesting:
        return Colors.teal;
      case readyForCollection:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  // Get estimated time to complete for a status
  static String getEstimatedTime(String status) {
    switch (status) {
      case vehicleReceived:
        return '1-2 hours';
      case initialDiagnosis:
        return '3-4 hours';
      case inInspection:
        return '5-6 hours';
      case partsAwaiting:
        return '1-2 days';
      case inRepair:
        return '1-2 days';
      case qualityCheck:
        return '2-3 hours';
      case finalTesting:
        return '1-2 hours';
      case readyForCollection:
        return 'Complete';
      default:
        return 'Unknown';
    }
  }
}

// Model for service tracking
class ServiceTracking {
  final String id;
  final String bookingId;
  final String? plateNumber;
  final String? serviceId; // legacy single service id
  final String? serviceType; // legacy single service type
  final List<String>? serviceIds; // multiple service ids
  final List<String>? serviceTypes; // multiple service types
  final String currentStatus;
  final DateTime updatedAt;
  final Map<String, StatusUpdate> statusUpdates;
  final String technicianId;
  final Technician? technician;
  final String? userId; // users.userId (e.g., U001)
  final String? uid; // Firebase Auth UID

  // Internal state for demo de-duplication
  static String? _lastDemoStatus;
  static String? _lastDemoTechId;
  static int _demoCounter = 0;

  ServiceTracking({
    required this.id,
    required this.bookingId,
    this.plateNumber,
    this.serviceId,
    this.serviceType,
    this.serviceIds,
    this.serviceTypes,
    required this.currentStatus,
    required this.updatedAt,
    required this.statusUpdates,
    required this.technicianId,
    this.technician,
    this.userId,
    this.uid,
  });

  // For demo data creation
  factory ServiceTracking.demo({required String bookingId, String? status}) {
    // Randomize a reasonable current status if not provided
    final flow = [
      TrackingBackend.vehicleReceived,
      TrackingBackend.initialDiagnosis,
      TrackingBackend.inInspection,
      TrackingBackend.partsAwaiting,
      TrackingBackend.inRepair,
      TrackingBackend.qualityCheck,
      TrackingBackend.finalTesting,
    ];

    // Seed with time + booking, add a local counter to avoid repeats on rapid inserts
    final baseSeed = DateTime.now().microsecondsSinceEpoch ^ bookingId.hashCode;
    final localCounter = _demoCounter++;
    final seed = baseSeed + localCounter * 101;
    final rand = Random((seed & 0x7fffffff));

    // Pick status using Random for better distribution
    int idx = rand.nextInt(flow.length);
    String currentStatus = status ?? flow[idx];

    // Choose a technician from a demo pool
    Technician tech = Technician.demo(
      seed: (((seed * 997) ^ idx) & 0x7fffffff),
    );

    // Ensure the latest two demo entries don't end up identical in status and technician
    if (status == null &&
        ServiceTracking._lastDemoStatus == currentStatus &&
        ServiceTracking._lastDemoTechId == tech.id) {
      final altIdx = (idx + 1 + rand.nextInt(flow.length - 1)) % flow.length;
      currentStatus = flow[altIdx];
      // pick a different tech id
      Technician altTech = tech;
      int safety = 0;
      while (altTech.id == tech.id && safety++ < 7) {
        final tSeed = ((seed + safety * 1337) & 0x7fffffff);
        altTech = Technician.demo(seed: tSeed);
      }
      tech = altTech;
    }

    // Record for next demo call
    ServiceTracking._lastDemoStatus = currentStatus;
    ServiceTracking._lastDemoTechId = tech.id;

    // Create sample status updates
    final statusUpdates = <String, StatusUpdate>{};

    // Define the service flow in the proper order (logical progression of service)
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

    // Get index of the current status in the service flow
    int currentFlowIndex = serviceFlow.indexOf(currentStatus);

    // Determine which statuses to include based on current status
    List<String> includedStatuses = [];

    // Include all statuses up to and including the current status in the service flow
    includedStatuses = serviceFlow.sublist(0, currentFlowIndex + 1);

    // If the current status is Ready for Collection, include all statuses
    if (currentStatus == TrackingBackend.readyForCollection) {
      includedStatuses = serviceFlow;
    }

    for (int i = 0; i < includedStatuses.length; i++) {
      final status = includedStatuses[i];

      // Calculate days ago based on position in service flow
      final daysAgo = serviceFlow.length - serviceFlow.indexOf(status);

      // Generate different notes for each status, include booking-specific hint
      String notes;
      switch (status) {
        case TrackingBackend.vehicleReceived:
          notes =
              'Booking $bookingId received at service center. Honda Civic 2020 noted. Initial diagnostic scan captured; monitoring code P0420 (catalyst efficiency).';
          break;
        case TrackingBackend.initialDiagnosis:
          notes =
              'Initial diagnosis for $bookingId: carbon buildup in intake, catalyst efficiency low. Recommending intake cleaning and catalyst inspection.';
          break;
        case TrackingBackend.inInspection:
          notes =
              'Comprehensive inspection for $bookingId: catalyst deterioration confirmed, O2 sensor readings low, intake deposits moderate.';
          break;
        case TrackingBackend.partsAwaiting:
          notes =
              'Awaiting parts for $bookingId: OEM catalyst and O2 sensors, intake cleaning supplies. ETA 1-2 business days.';
          break;
        case TrackingBackend.inRepair:
          notes =
              'In repair for $bookingId: replacing catalyst, both O2 sensors, and performing intake cleaning (walnut blast).';
          break;
        case TrackingBackend.qualityCheck:
          notes =
              'Quality check for $bookingId: verifying catalyst and O2 installs, running diagnostics, intake cleanliness verified.';
          break;
        case TrackingBackend.finalTesting:
          notes =
              'Final testing for $bookingId: road test OK, idle stable, no DTCs, catalyst efficiency normal.';
          break;
        case TrackingBackend.readyForCollection:
          notes =
              'Booking $bookingId ready for collection. Repairs completed successfully and diagnostics clear.';
          break;
        default:
          notes = 'Update for $status stage';
      }

      // Only add images for completed stages
      List<String> imageUrls = [];
      if (serviceFlow.indexOf(status) < currentFlowIndex) {
        // Use a specific relevant image for each stage
        switch (status) {
          case TrackingBackend.vehicleReceived:
            imageUrls = [
              'https://images.unsplash.com/photo-1503376780353-7e6692767b70?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.initialDiagnosis:
            imageUrls = [
              'https://images.unsplash.com/photo-1593941707882-a5bba14938c7?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.inInspection:
            imageUrls = [
              'https://images.unsplash.com/photo-1507977800135-15546c52d235?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.partsAwaiting:
            imageUrls = [
              'https://images.unsplash.com/photo-1581092162384-8987c1d64718?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.inRepair:
            imageUrls = [
              'https://images.unsplash.com/photo-1530046339160-ce3e530c7d2f?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.qualityCheck:
            imageUrls = [
              'https://images.unsplash.com/photo-1600880292089-90a7e086ee0c?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.finalTesting:
            imageUrls = [
              'https://images.unsplash.com/photo-1623861397257-16141b928bee?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          case TrackingBackend.readyForCollection:
            imageUrls = [
              'https://images.unsplash.com/photo-1563720223185-11003d516935?w=800&h=600&auto=format&fit=crop',
            ];
            break;
          default:
            imageUrls = [
              'https://images.unsplash.com/photo-1551522435-a13afa10f103?w=800&h=600&auto=format&fit=crop',
            ];
        }
      }

      // Add estimated completion time for current status
      DateTime? estimatedCompletionTime;
      if (status == currentStatus &&
          status != TrackingBackend.readyForCollection) {
        // Base estimate per stage plus jitter to vary across bookings
        final baseHours = 6 + (serviceFlow.indexOf(status) * 6);
        final extraHours = (seed + i * 13) % 5; // 0..4
        final extraMins = (seed + i * 17) % 60; // 0..59
        estimatedCompletionTime = DateTime.now().add(
          Duration(hours: baseHours + extraHours, minutes: extraMins),
        );
      }

      // Set startAt and endAt times
      // Add small random jitter so multiple demos differ more
      final jitterMinutes = (seed + i * 37) % 180; // 0..179 minutes
      final baseDateTime = DateTime.now().subtract(
        Duration(days: daysAgo, minutes: jitterMinutes),
      );

      // Start time is the timestamp
      final DateTime startAt = baseDateTime;

      // End time is null for current stage, but set for completed stages
      DateTime? endAt;
      if (serviceFlow.indexOf(status) < currentFlowIndex) {
        // For completed stages, set an end time with varied hours and minutes
        final durationHours = 2 + ((seed + i * 11) % 7); // 2..8
        final durationMins = (seed + i * 19) % 45; // 0..44
        endAt = startAt.add(
          Duration(hours: durationHours, minutes: durationMins),
        );
      }

      statusUpdates[status] = StatusUpdate(
        status: status,
        timestamp: baseDateTime,
        notes: notes,
        imageUrls: imageUrls,
        estimatedCompletionTime: estimatedCompletionTime,
        startAt: startAt,
        endAt: endAt,
      );
    }

    // Randomize updatedAt slightly to avoid identical timestamps
    final updatedJitter = Duration(minutes: (seed % 240));
    return ServiceTracking(
      id: 'track-${DateTime.now().millisecondsSinceEpoch}',
      bookingId: bookingId,
      plateNumber: null,
      serviceId: null,
      serviceType: null,
      serviceIds: null,
      serviceTypes: null,
      currentStatus: currentStatus,
      updatedAt: DateTime.now().subtract(updatedJitter),
      statusUpdates: statusUpdates,
      technicianId: tech.id,
      technician: tech,
      userId: null,
      uid: null,
    );
  }

  factory ServiceTracking.fromMap(String id, Map<String, dynamic> data) {
    final updatesRaw = (data['stages'] as Map<String, dynamic>?);
    final updates = <String, StatusUpdate>{};
    if (updatesRaw != null) {
      updatesRaw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          updates[key] = StatusUpdate.fromMap(key, value);
        }
      });
    }

    return ServiceTracking(
      id: id,
      bookingId: (data['BookingID'] ?? data['bookingId'] ?? '') as String,
      plateNumber:
          (data['plateNumber'] ??
                  data['PlateNumber'] ??
                  data['plate'] ??
                  data['VehiclePlate'])
              as String?,
      serviceId: (data['ServiceID'] ?? data['serviceId']) as String?,
      serviceType: (data['serviceType'] ?? data['ServiceType']) as String?,
      serviceIds: (data['ServiceIDs'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      serviceTypes: (data['ServiceTypes'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      currentStatus:
          (data['status'] ??
                  data['currentStatus'] ??
                  TrackingBackend.vehicleReceived)
              as String,
      updatedAt: _toDateTime(data['updatedAt']) ?? DateTime.now(),
      statusUpdates: updates,
      technicianId:
          (data['TechnicianID'] ?? data['technicianId'] ?? '') as String,
      technician: null,
      userId: (data['UserID'] ?? data['userId']) as String?,
      uid: data['uid'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'TrackID': id,
      'BookingID': bookingId,
      if (plateNumber != null && plateNumber!.trim().isNotEmpty)
        'plateNumber': plateNumber,
      if (serviceId != null && serviceId!.trim().isNotEmpty)
        'ServiceID': serviceId,
      if (serviceType != null && serviceType!.trim().isNotEmpty)
        'serviceType': serviceType,
      if (serviceIds != null && serviceIds!.isNotEmpty)
        'ServiceIDs': serviceIds,
      if (serviceTypes != null && serviceTypes!.isNotEmpty)
        'ServiceTypes': serviceTypes,
      'status': currentStatus,
      'updatedAt': fs.FieldValue.serverTimestamp(),
      'stages': statusUpdates.map((k, v) => MapEntry(k, v.toMap())),
      'TechnicianID': technicianId,
      if (userId != null) 'UserID': userId,
      if (uid != null) 'uid': uid,
    };
  }

  // Sample tracking data for demo
  static List<ServiceTracking> getDemoTrackings() {
    return [
      ServiceTracking.demo(
        bookingId: 'BK-001',
        status: TrackingBackend.readyForCollection,
      ),
      ServiceTracking.demo(
        bookingId: 'BK-002',
        status: TrackingBackend.inRepair,
      ),
      ServiceTracking.demo(
        bookingId: 'BK-003',
        status: TrackingBackend.partsAwaiting,
      ),
    ];
  }
}

// Status update for a specific stage
class StatusUpdate {
  final String status;
  final DateTime timestamp;
  final String notes;
  final List<String> imageUrls;
  final DateTime? estimatedCompletionTime;
  final DateTime? startAt; // Start time of the stage
  final DateTime? endAt; // End time of the stage (null if not completed)

  StatusUpdate({
    required this.status,
    required this.timestamp,
    required this.notes,
    required this.imageUrls,
    this.estimatedCompletionTime,
    this.startAt,
    this.endAt,
  });

  factory StatusUpdate.fromMap(String status, Map<String, dynamic> data) {
    return StatusUpdate(
      status: status,
      timestamp: _toDateTime(data['timestamp']) ?? DateTime.now(),
      notes: (data['notes'] ?? '') as String,
      imageUrls:
          (data['imageUrls'] as List?)?.cast<String>() ??
          (data['photoUrls'] as List?)?.cast<String>() ??
          <String>[],
      estimatedCompletionTime: _toDateTime(data['estimatedCompletionTime']),
      startAt: _toDateTime(data['startAt']),
      endAt: _toDateTime(data['endAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'timestamp': fs.FieldValue.serverTimestamp(),
      'notes': notes,
      'imageUrls': imageUrls,
      if (estimatedCompletionTime != null)
        'estimatedCompletionTime': estimatedCompletionTime,
      if (startAt != null) 'startAt': startAt,
      if (endAt != null) 'endAt': endAt,
    };
  }
}

// Technician model
class Technician {
  final String id;
  final String name;
  final String avatarUrl;
  final int yearsExperience;
  final List<String> skills;

  Technician({
    required this.id,
    required this.name,
    required this.avatarUrl,
    required this.yearsExperience,
    required this.skills,
  });

  // A small pool of demo technicians to improve variety
  static final List<Technician> _demoPool = [
    Technician(
      id: 'T001',
      name: 'Alex Johnson',
      avatarUrl: 'https://i.pravatar.cc/150?img=12',
      yearsExperience: 8,
      skills: [
        'Engine Repair',
        'Brake Systems',
        'Diagnostics',
        'Electrical Systems',
      ],
    ),
    Technician(
      id: 'T002',
      name: 'Maria Garcia',
      avatarUrl: 'https://i.pravatar.cc/150?img=32',
      yearsExperience: 6,
      skills: ['Diagnostics', 'Suspension', 'Air Conditioning'],
    ),
    Technician(
      id: 'T003',
      name: 'Liam Smith',
      avatarUrl: 'https://i.pravatar.cc/150?img=5',
      yearsExperience: 10,
      skills: ['Transmission', 'Engine Repair', 'Drivetrain'],
    ),
    Technician(
      id: 'T004',
      name: 'Sofia Lee',
      avatarUrl: 'https://i.pravatar.cc/150?img=47',
      yearsExperience: 7,
      skills: ['Electrical Systems', 'Infotainment', 'Diagnostics'],
    ),
    Technician(
      id: 'T005',
      name: 'Noah Patel',
      avatarUrl: 'https://i.pravatar.cc/150?img=68',
      yearsExperience: 9,
      skills: ['Brake Systems', 'Steering', 'Suspension'],
    ),
    Technician(
      id: 'T006',
      name: 'Emma Wilson',
      avatarUrl: 'https://i.pravatar.cc/150?img=15',
      yearsExperience: 5,
      skills: ['Air Conditioning', 'Cooling System', 'Diagnostics'],
    ),
    Technician(
      id: 'T007',
      name: 'Ethan Chen',
      avatarUrl: 'https://i.pravatar.cc/150?img=25',
      yearsExperience: 11,
      skills: ['Engine Repair', 'Exhaust', 'Diagnostics'],
    ),
    Technician(
      id: 'T008',
      name: 'Olivia Brown',
      avatarUrl: 'https://i.pravatar.cc/150?img=9',
      yearsExperience: 4,
      skills: ['Detailing', 'Quality Check', 'Final Testing'],
    ),
  ];

  factory Technician.demo({int? seed}) {
    if (_demoPool.isEmpty) {
      // Fallback to a default technician if pool is empty for any reason
      return Technician(
        id: 'T001',
        name: 'Alex Johnson',
        avatarUrl: 'https://i.pravatar.cc/150?img=12',
        yearsExperience: 8,
        skills: [
          'Engine Repair',
          'Brake Systems',
          'Diagnostics',
          'Electrical Systems',
        ],
      );
    }
    final r = seed == null ? Random() : Random(seed);
    return _demoPool[r.nextInt(_demoPool.length)];
  }

  factory Technician.fromMap(String id, Map<String, dynamic> data) {
    return Technician(
      id: id,
      name: (data['name'] ?? data['fullName'] ?? 'Technician') as String,
      avatarUrl: (data['avatarUrl'] ?? data['photoUrl'] ?? '') as String,
      yearsExperience: (data['yearsExperience'] ?? 0) is int
          ? data['yearsExperience'] as int
          : int.tryParse((data['yearsExperience'] ?? '0').toString()) ?? 0,
      skills: (data['skills'] as List?)?.cast<String>() ?? <String>[],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'TechnicianID': id,
      'name': name,
      'avatarUrl': avatarUrl,
      'yearsExperience': yearsExperience,
      'skills': skills,
      'position': skills.isNotEmpty
          ? '${skills.first} Technician'
          : 'Technician',
    };
  }
}

// Chat message model
class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String message;
  final DateTime timestamp;
  final bool isFromTechnician;
  final List<String> images;

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.message,
    required this.timestamp,
    required this.isFromTechnician,
    this.images = const [],
  });

  factory ChatMessage.fromMap(String id, Map<String, dynamic> data) {
    return ChatMessage(
      id: id,
      senderId:
          (data['UserID'] ?? data['TechnicianID'] ?? data['senderId'] ?? '')
              as String,
      senderName: (data['senderName'] ?? '') as String,
      message: (data['text'] ?? data['message'] ?? '') as String,
      timestamp: _toDateTime(data['date']) ?? DateTime.now(),
      isFromTechnician:
          data['TechnicianID'] != null &&
          (data['TechnicianID'] as String).isNotEmpty,
      images: (data['images'] as List?)?.cast<String>() ?? <String>[],
    );
  }

  Map<String, dynamic> toMap({
    required String trackId,
    String? userId,
    String? technicianId,
  }) {
    return {
      'ChatID': id,
      'TrackID': trackId,
      'text': message,
      'date': fs.FieldValue.serverTimestamp(),
      if (userId != null) 'UserID': userId,
      if (technicianId != null) 'TechnicianID': technicianId,
      if (senderName.isNotEmpty) 'senderName': senderName,
      'images': images,
    };
  }
}

DateTime? _toDateTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is fs.Timestamp) return v.toDate();
  return DateTime.tryParse(v.toString());
}
