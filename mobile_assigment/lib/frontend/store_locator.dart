import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:url_launcher/url_launcher.dart';

class StoreLocatorPage extends StatefulWidget {
  const StoreLocatorPage({super.key});

  @override
  State<StoreLocatorPage> createState() => _StoreLocatorPageState();
}

class _StoreLocatorPageState extends State<StoreLocatorPage> {
  final MapController _mapController = MapController();

  LatLng? _myLocation;
  String? _locationError;

  List<_ShopData> _shops = const [];
  final Map<String, LatLng> _shopPositions = {};
  final Map<String, String> _imageUrls = {};

  // no programmatic recentering; we build the map once we have location

  // No explicit loading state; show map immediately.

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final loc = await _getUserLocation();
      setState(() => _myLocation = loc);
    } catch (e) {
      setState(() => _locationError = e.toString());
    }

    await _fetchShops();
    if (mounted) setState(() {});
  }

  Future<LatLng> _getUserLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission denied');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    return LatLng(pos.latitude, pos.longitude);
  }

  // Removed auto-center-on-build to avoid delaying tile requests

  Future<void> _fetchShops() async {
    try {
      final qs = await FirebaseFirestore.instance.collection('Shop').get();
      final shops = qs.docs
          .map((d) => _ShopData.fromSnapshot(d))
          .where((s) => s != null)
          .cast<_ShopData>()
          .toList();

      _shops = shops;

      // Use exact coordinates if present; otherwise derive a stable
      // pseudo-random nearby point seeded from the shop id so it is
      // deterministic across runs.
      final center = _myLocation ?? const LatLng(3.1390, 101.6869);
      for (final s in shops) {
        if (s.lat != null && s.lng != null) {
          _shopPositions[s.id] = LatLng(s.lat!, s.lng!);
        } else {
          _shopPositions[s.id] = _deterministicNearby(
            key: s.id,
            center: center,
            minRadiusMeters: 1200,
            maxRadiusMeters: 3500,
          );
        }
        // Prepare image urls if provided directly
        if (s.imageUrl != null && s.imageUrl!.isNotEmpty) {
          _imageUrls[s.id] = s.imageUrl!;
        }
      }

      // Resolve Firebase Storage refs to download URLs
      await _resolveImageUrlsForStorageRefs(shops);
    } catch (e) {
      // Keep shops empty but show a SnackBar for visibility.
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to load shops: $e')));
      }
    }
  }

  Future<void> _resolveImageUrlsForStorageRefs(List<_ShopData> shops) async {
    final storage = FirebaseStorage.instance;
    final futures = <Future<void>>[];
    for (final s in shops) {
      if (_imageUrls.containsKey(s.id)) continue; // already have a direct URL
      final refPath = s.imageRef;
      if (refPath == null || refPath.isEmpty) continue;
      futures.add(() async {
        try {
          final url = await storage.ref(refPath).getDownloadURL();
          _imageUrls[s.id] = url;
          if (mounted) setState(() {});
        } catch (_) {
          // ignore failures for missing images
        }
      }());
    }
    await Future.wait(futures);
  }

  LatLng _deterministicNearby({
    required String key,
    required LatLng center,
    required int minRadiusMeters,
    required int maxRadiusMeters,
  }) {
    // Build a stable seed from the key (do not use String.hashCode).
    int seed = 0;
    for (final unit in key.codeUnits) {
      seed = (seed * 131 + unit) & 0x7fffffff;
    }
    final rand = Random(seed);
    final radiusMeters =
        minRadiusMeters + rand.nextInt(maxRadiusMeters - minRadiusMeters + 1);
    final r = radiusMeters / 111320; // meters to degrees roughly
    final t = 2 * pi * (rand.nextDouble());
    // Use a simple distribution that stays within the circle
    final u = rand.nextDouble();
    final rr = sqrt(u) * r; // more uniform over area
    final dx = rr * cos(t);
    final dy = rr * sin(t);
    return LatLng(center.latitude + dy, center.longitude + dx);
  }

  Future<void> _openDirectionsTo(LatLng destination) async {
    final dest = '${destination.latitude},${destination.longitude}';
    final origin = _myLocation != null
        ? '${_myLocation!.latitude},${_myLocation!.longitude}'
        : null;

    // Try Google Maps app first
    final appUri = Uri.parse(
      'google.navigation:q=$dest&mode=d',
    ); // turn-by-turn if available
    final query = origin != null
        ? 'api=1&origin=$origin&destination=$dest&travelmode=driving'
        : 'api=1&destination=$dest&travelmode=driving';
    final webUri = Uri.parse('https://www.google.com/maps/dir/?$query');

    try {
      if (await canLaunchUrl(appUri)) {
        await launchUrl(appUri, mode: LaunchMode.externalApplication);
        return;
      }
    } catch (_) {
      // fallback to web below
    }
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  void _showShopDetails(_ShopData shop, LatLng position) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        final imageUrl = _imageUrls[shop.id] ?? shop.imageUrl;
        final h = MediaQuery.of(ctx).size.height;
        return SizedBox(
          height: h * 0.5,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageUrl != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: (h * 0.5 * 0.38).clamp(120.0, 200.0),
                      width: double.infinity,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          alignment: Alignment.center,
                          child: const Icon(Icons.store, size: 64),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.store, size: 28),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shop ${shop.shopId}',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shop.location,
                            style: Theme.of(ctx).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _infoRow('Location', shop.location),
                _infoRow('Status', shop.status),
                _infoRow('Open', shop.openAt),
                _infoRow('Close', shop.closeAt),
                _infoRow('Working Days', shop.workingDays),
                const Spacer(),
                Wrap(
                  spacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _openDirectionsTo(position);
                      },
                      icon: const Icon(Icons.navigation),
                      label: const Text('Directions'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Don't render the map until we have a real location so
    // the page always starts centered on the user.
    if (_myLocation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Store Locator')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.my_location, size: 48, color: Colors.blueGrey),
              const SizedBox(height: 12),
              const Text('Getting your current location...'),
              if (_locationError != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Location unavailable: ${_locationError!}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ],
            ],
          ),
        ),
      );
    }

    final center = _myLocation!;

    return Scaffold(
      appBar: AppBar(title: const Text('Store Locator')),
      body: Stack(
        children: [
          FlutterMap(
            key: ValueKey('map_${center.latitude}_${center.longitude}'),
            mapController: _mapController,
            options: MapOptions(initialCenter: center, initialZoom: 14),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.mobile_assignment',
                maxNativeZoom: 19,
                tileProvider: NetworkTileProvider(),
              ),
              MarkerLayer(
                markers: [
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 32,
                      ),
                    ),
                  // Shop markers
                  ..._shops.map((s) {
                    final pos = _shopPositions[s.id];
                    if (pos == null)
                      return const Marker(
                        point: LatLng(0, 0),
                        child: SizedBox.shrink(),
                      );
                    return Marker(
                      point: pos,
                      width: 44,
                      height: 44,
                      child: GestureDetector(
                        onTap: () => _showShopDetails(s, pos),
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.red,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ],
          ),
          if (_locationError != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 20,
              child: Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Location unavailable: $_locationError',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: _myLocation == null
          ? null
          : FloatingActionButton(
              onPressed: () => _mapController.move(_myLocation!, 15),
              child: const Icon(Icons.center_focus_strong),
            ),
    );
  }
}

class _ShopData {
  final String id;
  final String shopId;
  final String location;
  final String openAt;
  final String closeAt;
  final String status;
  final String workingDays;
  final double? lat;
  final double? lng;
  final String? imageUrl; // direct URL to display
  final String? imageRef; // Firebase Storage path to resolve

  const _ShopData({
    required this.id,
    required this.shopId,
    required this.location,
    required this.openAt,
    required this.closeAt,
    required this.status,
    required this.workingDays,
    this.lat,
    this.lng,
    this.imageUrl,
    this.imageRef,
  });

  static _ShopData? fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    double? parseDouble(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final lat = parseDouble(
      data['lat'] ?? data['latitude'] ?? data['Lat'] ?? data['Latitude'],
    );
    final lng = parseDouble(
      data['lng'] ?? data['longitude'] ?? data['Lng'] ?? data['Longitude'],
    );
    // Try to pick up image fields flexibly
    String? pickString(Map<String, dynamic> m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v == null) continue;
        final s = v.toString();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

    final imageUrl = pickString(data, [
      'imageUrl',
      'imageURL',
      'ImageUrl',
      'photoUrl',
      'photoURL',
      'image',
    ]);
    final imageRef = pickString(data, [
      'imageRef',
      'imagePath',
      'storagePath',
      'photoRef',
    ]);

    return _ShopData(
      id: doc.id,
      shopId: (data['ShopId'] ?? data['shopId'] ?? '').toString(),
      location: (data['Location'] ?? '').toString(),
      openAt: (data['OpenAt'] ?? '').toString(),
      closeAt: (data['CloseAt'] ?? '').toString(),
      status: (data['Status'] ?? '').toString(),
      workingDays: (data['WorkingDays'] ?? '').toString(),
      lat: lat,
      lng: lng,
      imageUrl: imageUrl,
      imageRef: imageRef,
    );
  }
}
