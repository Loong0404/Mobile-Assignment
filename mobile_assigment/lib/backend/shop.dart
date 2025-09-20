import 'package:cloud_firestore/cloud_firestore.dart' as fs;

class Shop {
  final String id;
  final String shopId;
  final String location;
  final String workingDays; // e.g. "Mon-Sun"
  final String openAt;      // "10:00:00"
  final String closeAt;     // "20:00:00"
  final String status;      // "Open"/"Closed"

  Shop({
    required this.id,
    required this.shopId,
    required this.location,
    required this.workingDays,
    required this.openAt,
    required this.closeAt,
    required this.status,
  });

  factory Shop.fromSnap(fs.DocumentSnapshot<Map<String, dynamic>> s) {
    final d = s.data() ?? {};
    final sid = (d['ShopID'] ?? d['ShopId'] ?? s.id) as String;
    return Shop(
      id: s.id,
      shopId: sid,
      location: (d['Location'] as String?) ?? '',
      workingDays: (d['WorkingDays'] as String?) ?? '',
      openAt: (d['OpenAt'] as String?) ?? '00:00:00',
      closeAt: (d['CloseAt'] as String?) ?? '23:59:00',
      status: (d['Status'] as String?) ?? 'Open',
    );
  }
}

abstract class ShopBackend {
  static ShopBackend instance = FirebaseShopBackend();

  Stream<List<Shop>> watchShops();
  Future<List<Shop>> listShops();
}

class FirebaseShopBackend implements ShopBackend {
  final fs.CollectionReference<Map<String, dynamic>> col =
  fs.FirebaseFirestore.instance.collection('Shop');

  @override
  Stream<List<Shop>> watchShops() =>
      col.orderBy('ShopId').snapshots().map((q) => q.docs.map(Shop.fromSnap).toList());

  @override
  Future<List<Shop>> listShops() async {
    final q = await col.orderBy('ShopId').get();
    return q.docs.map(Shop.fromSnap).toList();
  }
}
