import 'dart:async';
import 'package:flutter/material.dart';
import '../backend/shop.dart';
import '../main.dart';
import 'shop_schedule.dart';

enum ShopFilter { all, open, closed }

class ShopListPage extends StatefulWidget {
  const ShopListPage({super.key});
  @override
  State<ShopListPage> createState() => _ShopListPageState();
}

class _ShopListPageState extends State<ShopListPage> {
  ShopFilter _filter = ShopFilter.all;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Set<int> _parseWorkingDays(String s) {
    final map = {'mon':1,'tue':2,'wed':3,'thu':4,'fri':5,'sat':6,'sun':7};
    final out = <int>{};
    final text = s.trim().toLowerCase();
    if (text.isEmpty) return out;
    for (final part in text.split(',')) {
      final p = part.trim();
      if (p.contains('-')) {
        final arr = p.split('-').map((e) => e.trim()).toList();
        if (arr.length == 2 && map.containsKey(arr[0]) && map.containsKey(arr[1])) {
          int start = map[arr[0]]!, end = map[arr[1]]!;
          if (start <= end) for (int d = start; d <= end; d++) out.add(d);
          else { for (int d = start; d <= 7; d++) out.add(d); for (int d = 1; d <= end; d++) out.add(d); }
        }
      } else if (map.containsKey(p)) { out.add(map[p]!); }
    }
    return out;
  }

  int _toMinutes(String t) {
    final p = t.split(':'); final h = int.tryParse(p[0]) ?? 0; final m = int.tryParse(p[1]) ?? 0;
    return h * 60 + m;
  }

  bool _isOpenNow(Shop s, DateTime now) {
    if (s.status.toLowerCase() != 'open') return false;
    final days = _parseWorkingDays(s.workingDays);
    if (days.isNotEmpty && !days.contains(now.weekday)) return false;
    final o = _toMinutes(s.openAt), c = _toMinutes(s.closeAt), cur = now.hour*60+now.minute;
    if (o <= c) return cur >= o && cur < c; // 当天
    return cur >= o || cur < c;             // 跨午夜
  }

  String _fmtTime(String t) => t.length >= 5 ? t.substring(0, 5) : t;

  @override
  Widget build(BuildContext context) {
    final green = WmsApp.grabGreen;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shops'),
        actions: [
          PopupMenuButton<ShopFilter>(
            tooltip: 'Filter',
            initialValue: _filter,
            onSelected: (v) => setState(() => _filter = v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: ShopFilter.all, child: Text('All')),
              PopupMenuItem(value: ShopFilter.open, child: Text('Only Open')),
              PopupMenuItem(value: ShopFilter.closed, child: Text('Only Closed')),
            ],
            icon: const Icon(Icons.filter_list),
          ),
        ],
      ),
      body: StreamBuilder<List<Shop>>(
        stream: ShopBackend.instance.watchShops(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shops = snap.data ?? const <Shop>[];
          if (shops.isEmpty) return const Center(child: Text('No shops available.'));

          final now = DateTime.now();
          final list = shops.map((s) => (s, _isOpenNow(s, now))).where((pair) {
            switch (_filter) {
              case ShopFilter.all: return true;
              case ShopFilter.open: return pair.$2;
              case ShopFilter.closed: return !pair.$2;
            }
          }).toList();

          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (_, i) {
              final (s, open) = list[i];
              final color = open ? green : Colors.red;
              final hoursText = '${s.workingDays} ${_fmtTime(s.openAt)}–${_fmtTime(s.closeAt)}';
              return Container(
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: Color(0x1F000000), width: 1)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.store_mall_directory_outlined),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.location, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(hoursText, style: const TextStyle(color: Colors.black54), overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'View schedule',
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ShopSchedulePage(shopId: s.shopId, title: 'Schedule'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.schedule),
                                iconSize: 18,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Chip(
                          label: Text(open ? 'OPEN' : 'CLOSED'),
                          visualDensity: VisualDensity.compact,
                          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                          backgroundColor: color.withOpacity(.12),
                          side: BorderSide(color: color),
                          labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                          padding: EdgeInsets.zero,
                        ),
                        const SizedBox(height: 4),
                        Text(s.shopId, style: const TextStyle(color: Colors.black45, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
