// lib/frontend/schedule.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../backend/shop.dart';
import '../main.dart';
import '../backend/schedule_view.dart' as sv;


/// 从 Shops 页“⏰”打开：显示今天/明天/后天；左右滑动；只读
class ShopSchedulePage extends StatefulWidget {
  const ShopSchedulePage({super.key, required this.shopId, this.title});
  final String shopId;
  final String? title;

  @override
  State<ShopSchedulePage> createState() => _ShopSchedulePageState();
}

class _ShopSchedulePageState extends State<ShopSchedulePage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 只读页面：不写库。每分钟 tick 刷新一下状态显示。
    _ticker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  List<DateTime> get _days =>
      List.generate(3, (i) => _todayStart.add(Duration(days: i)));

  String _fmtTab(DateTime d) => DateFormat('EEE dd MMM').format(d); // Tue 16 Sep
  String _fmtHM(DateTime d) => DateFormat('HH:mm').format(d);

  @override
  Widget build(BuildContext context) {
    final green = WmsApp.grabGreen;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? 'Schedule'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: StreamBuilder<List<Shop>>(
              stream: ShopBackend.instance.watchShops(),
              builder: (context, shopSnap) {
                if (!shopSnap.hasData) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                return TabBar(
                  isScrollable: true,
                  tabs: [for (final d in _days) Tab(text: _fmtTab(d))],
                );
              },
            ),
          ),
        ),
        body: StreamBuilder<List<Shop>>(
          stream: ShopBackend.instance.watchShops(),
          builder: (context, shopSnap) {
            if (!shopSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final shops = shopSnap.data!;
            if (shops.isEmpty) {
              return const Center(child: Text('No shops configured.'));
            }
            final shop = shops.firstWhere(
                  (e) => e.shopId == widget.shopId,
              orElse: () => shops.first,
            );

            return TabBarView(
              children: [
                for (final day in _days)
                  _DayScheduleList(
                    shopId: shop.shopId,
                    day: day,
                    fmtHM: _fmtHM,
                    green: green,
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DayScheduleList extends StatelessWidget {
  const _DayScheduleList({
    required this.shopId,
    required this.day,
    required this.fmtHM,
    required this.green,
  });

  final String shopId;
  final DateTime day;
  final String Function(DateTime) fmtHM;
  final Color green;

  @override
  Widget build(BuildContext context) {
    final nextDay = day.add(const Duration(days: 1));

    return StreamBuilder<List<sv.Schedule>>(
      stream: sv.ScheduleViewBackend.instance.watchForShopInRange(
        shopId: shopId,
        startInclusive: day,
        endExclusive: nextDay,
      ),
      builder: (context, snap) {
        final list = snap.data ?? const <sv.Schedule>[];
        if (snap.connectionState == ConnectionState.waiting && list.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return const Center(child: Text('No time slots for this day.'));
        }

        return ListView.separated(
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = list[i];
            final isFree = s.status.toLowerCase() == 'free';
            final color = isFree ? green : Colors.orange;
            final cap = '${s.currentCapacity}/${s.totalCapacity}';

            return ListTile(
              leading: const Icon(Icons.access_time),
              title: Text(
                '${fmtHM(s.startAt)} - ${fmtHM(s.endAt)}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('Capacity $cap'),
              trailing: Chip(
                label: Text(s.status),
                backgroundColor: color.withOpacity(.12),
                side: BorderSide(color: color),
                labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
              // 只读：无 onTap
            );
          },
        );
      },
    );
  }
}
