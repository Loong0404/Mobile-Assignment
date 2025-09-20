import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class Service {
  final String id;
  final String serviceId;   // ST001...
  final String serviceType; // "Oil Change" / "Others"...

  Service({required this.id, required this.serviceId, required this.serviceType});

  factory Service.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    return Service(
      id: s.id,
      serviceId: (d['ServiceID'] as String?) ?? s.id,
      serviceType: (d['serviceType'] as String?) ?? '',
    );
  }
}

abstract class ServiceBackend {
  static ServiceBackend instance = FirebaseServiceBackend();

  Stream<List<Service>> watchServices();
}

class FirebaseServiceBackend implements ServiceBackend {
  final fs.CollectionReference<Map<String, dynamic>> col =
  fs.FirebaseFirestore.instance.collection('Service');

  @override
  Stream<List<Service>> watchServices() =>
      col.orderBy('ServiceID').snapshots().map((q) => q.docs.map(Service.fromSnap).toList());
}
