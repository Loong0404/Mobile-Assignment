// lib/frontend/shop_schedule.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../backend/schedule.dart' as sched; // ← 别名，避免与别处同名

class ShopSchedulePage extends StatefulWidget {
  final String shopId;
  final String title;
  const ShopSchedulePage({
    super.key,
    required this.shopId,
    this.title = 'Schedule',
  });

  @override
  State<ShopSchedulePage> createState() => _ShopSchedulePageState();
}

class _ShopSchedulePageState extends State<ShopSchedulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late final DateTime _start; // 明天 00:00（本地）

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    _start = today.add(const Duration(days: 1)); // 明天

    // 兜底：只为当前店补齐明/后/大后（不清空已有）
    sched.ScheduleUpdater.instance.ensure3DaysForShopIfMissing(widget.shopId);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(3, (i) => _start.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: days.map((d) {
            final wd = DateFormat('E').format(d);      // Wed
            final mdy = DateFormat('MMM d').format(d); // Sep 17
            return Tab(height: 44, text: '$wd  $mdy');
          }).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: days.map((d) => _DayList(shopId: widget.shopId, day: d)).toList(),
      ),
    );
  }
}

class _DayList extends StatelessWidget {
  final String shopId;
  final DateTime day;
  const _DayList({required this.shopId, required this.day});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<sched.Schedule>>(
      stream: sched.ScheduleView.instance.watchForShopOnDate(
        shopId: shopId,
        dayStart: day, // 当天 00:00
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Error: ${snap.error}',
                  style: const TextStyle(color: Colors.red)),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const <sched.Schedule>[];
        if (list.isEmpty) {
          return const Center(child: Text('No schedule for this day'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = list[i];

            final time =
                '${DateFormat.Hm().format(s.startAt)} - ${DateFormat.Hm().format(s.endAt)}';

            // ▶ 满位逻辑：容量已满或状态为 full
            final isFull =
                (s.currentCapacity >= s.totalCapacity) ||
                    s.status.toLowerCase() == 'full';

            final isFree = s.status.toLowerCase() == 'free' && !isFull;

            // 颜色：Free 绿色，Full 红色，其它（例如 Hold/Busy）橙色
            final Color color = isFull
                ? Colors.red
                : (isFree ? Colors.green : Colors.orange);

            final String chipText = isFull
                ? 'FULL'
                : (isFree ? 'FREE' : s.status.toUpperCase());

            return ListTile(
              title: Text(time, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Capacity: ${s.currentCapacity}/${s.totalCapacity}'
                    '${isFull ? " (Full)" : ""}',
              ),
              trailing: Chip(
                label: Text(chipText),
                backgroundColor: color.withOpacity(.1),
                labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
                side: BorderSide(color: color),
              ),
              onTap: null, // user 仅查看
            );
          },
        );
      },
    );
  }
}
