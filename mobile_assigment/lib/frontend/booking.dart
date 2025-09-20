// lib/frontend/booking.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../backend/shop.dart';
import '../backend/schedule_view.dart';
import '../backend/service.dart';
import '../backend/booking_backend.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  String? _shopId;

  // 选择三天（明天起算）
  int _dayIndex = 0;
  DateTime get _day0 {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  // 选中的时段范围
  String? _startId;
  String? _endId;
  List<Schedule> _pickedSlots = const [];

  // 选择的服务
  final Set<String> _serviceIds = {};
  final TextEditingController _othersCtrl = TextEditingController();

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Others 文本变化时刷新按钮可用态（解决“要再点一次 Others 才能提交”的问题）
    _othersCtrl.addListener(() => setState(() {}));

    // 开启“过期 & 等位晋升”后台任务
    BookingBackend.instance.startRealtimeAutoExpire();
  }

  @override
  void dispose() {
    _othersCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('EEE  MMM d');
    const startOffsetDays = 1; // 明天
    final days =
    List.generate(3, (i) => _day0.add(Duration(days: i + startOffsetDays)));

    return Scaffold(
      appBar: AppBar(title: const Text('New Booking')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          // —— 当前时间 —— //
          const _NowClock(),
          const SizedBox(height: 12),

          // ------------------- Shop -------------------
          _Field(
            label: 'Facility (Shop) *',
            child: StreamBuilder<List<Shop>>(
              stream: ShopBackend.instance.watchShops(),
              builder: (context, snap) {
                final shops = (snap.data ?? const <Shop>[]);
                final validValue =
                shops.any((s) => s.shopId == _shopId) ? _shopId : null;

                return DropdownButton<String>(
                  isExpanded: true,
                  value: validValue,
                  hint: const Text('Select a shop'),
                  items: shops
                      .map((s) => DropdownMenuItem(
                    value: s.shopId,
                    child: Text('${s.location} (${s.shopId})'),
                  ))
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      _shopId = v;
                      _startId = null;
                      _endId = null;
                      _pickedSlots = const [];
                    });
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // ------------------- Date -------------------
          _Field(
            label: 'Booking Date *',
            child: SegmentedButton<int>(
              segments: [
                for (int i = 0; i < 3; i++)
                  ButtonSegment(
                    value: i,
                    label: Text(dateFmt.format(days[i])),
                  ),
              ],
              selected: {_dayIndex},
              onSelectionChanged: (set) {
                setState(() {
                  _dayIndex = set.first;
                  _startId = null;
                  _endId = null;
                  _pickedSlots = const [];
                });
              },
            ),
          ),
          const SizedBox(height: 12),

          // ------------------- Time Range（预约） -------------------
          _Field(
            label: 'Time Range for Booking *',
            child: _SlotRangePicker(
              shopId: _shopId,
              day: days[_dayIndex],
              startId: _startId,
              endId: _endId,
              includeFull: false, // 预约：只显示可约
              onChanged: (s, e, slots) {
                setState(() {
                  _startId = s;
                  _endId = e;
                  _pickedSlots = slots;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'If your preferred time is FULL, use the waitlist below.',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // ------------------- Time Range（等位） -------------------
          _Field(
            label: 'Time Range for Waitlist',
            child: _SlotRangePicker(
              shopId: _shopId,
              day: days[_dayIndex],
              startId: null,
              endId: null,
              includeFull: true, // 等位：可选 FULL
              onChanged: (s, e, slots) {
                // 与上面的选择互斥，选了等位区就清掉预约区，反之亦然
                setState(() {
                  _startId = null;
                  _endId = null;
                  _pickedSlots = slots;
                });
              },
            ),
          ),
          const SizedBox(height: 12),

          // ------------------- Services -------------------
          _Field(
            label: 'Service Type (multiple) *',
            child: StreamBuilder<List<Service>>(
              stream: ServiceBackend.instance.watchServices(),
              builder: (context, snap) {
                final services = (snap.data ?? const <Service>[]);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: -8,
                      children: [
                        for (final s in services)
                          FilterChip(
                            label: Text(s.serviceType),
                            selected: _serviceIds.contains(s.serviceId),
                            onSelected: (sel) {
                              setState(() {
                                if (sel) {
                                  _serviceIds.add(s.serviceId);
                                } else {
                                  _serviceIds.remove(s.serviceId);
                                }
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_needsOthersField(services))
                      TextField(
                        controller: _othersCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Please describe “Others”',
                          hintText: 'e.g. unusual noise from engine…',
                        ),
                        maxLines: 2,
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 16),

          // ------------------- Vehicle -------------------
          _Field(
            label: 'Plate Number',
            child: DropdownButton<String>(
              isExpanded: true,
              value: 'VAE6823', // 先用 dummy
              items: const [
                DropdownMenuItem(value: 'VAE6823', child: Text('VAE6823')),
              ],
              onChanged: (_) {},
            ),
          ),
          const SizedBox(height: 24),

          // ------------------- Actions -------------------
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _canCommon ? _preview : null,
                  child: const Text('Review'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _saving ? null : (_canBook ? _submitBooking : null),
                  child: _saving
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('Submit Booking'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _saving ? null : (_canWait ? _submitWaitlist : null),
            icon: const Icon(Icons.hourglass_bottom),
            label: const Text('Join Waitlist (can pick FULL slots)'),
          ),

          const SizedBox(height: 24),

          // ------------------- Bookings (实时) -------------------
          const _PendingBookingsSection(userId: 'U002'),
          const SizedBox(height: 16),
          const _WaitlistSection(userId: 'U002'),
          const SizedBox(height: 16),
          const _ExpiredBookingsSection(userId: 'U002'),
        ],
      ),
    );
  }

  bool _needsOthersField(List<Service> all) {
    // 选了 Others（ID=ST004 或名称等于 others）才显示文本框
    return _serviceIds.any((id) =>
    id.toUpperCase() == 'ST004' ||
        all
            .firstWhere(
              (x) => x.serviceId == id,
          orElse: () =>
              Service(id: '', serviceId: '', serviceType: ''),
        )
            .serviceType
            .toLowerCase() ==
            'others');
  }

  bool get _canCommon =>
      _shopId != null && _pickedSlots.isNotEmpty && _serviceIds.isNotEmpty;

  bool get _needsOthersButEmpty =>
      _serviceIds.any((id) => id.toUpperCase() == 'ST004') &&
          _othersCtrl.text.trim().isEmpty;

  bool get _canBook => _canCommon && !_needsOthersButEmpty;

  bool get _canWait => _canCommon && !_needsOthersButEmpty;

  void _preview() {
    final tf = DateFormat('yyyy-MM-dd HH:mm');
    final start = _pickedSlots.first.startAt;
    final end = _pickedSlots.last.endAt;
    final msg = StringBuffer()
      ..writeln('Shop: $_shopId')
      ..writeln('From: ${tf.format(start)}')
      ..writeln('To  : ${tf.format(end)}')
      ..writeln('Slots: ${_pickedSlots.length}')
      ..writeln('Services: ${_serviceIds.join(', ')}')
      ..writelnIf(_othersCtrl.text.trim().isNotEmpty,
          'Others: ${_othersCtrl.text.trim()}');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Your selection'),
        content: Text(msg.toString()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  Future<void> _submitBooking() async {
    setState(() => _saving = true);
    try {
      if (_shopId == null || _pickedSlots.isEmpty || _serviceIds.isEmpty) {
        throw Exception('Please complete the form.');
      }
      final bookingId = await BookingBackend.instance.createBooking(
        userId: 'U002', // dummy
        shopId: _shopId!,
        plateNumber: 'VAE6823', // dummy
        scheduleIds: _pickedSlots.map((s) => s.scheduleId).toList(),
        serviceIds: _serviceIds.toList(),
        othersText:
        _othersCtrl.text.trim().isEmpty ? null : _othersCtrl.text.trim(),
      );

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Success'),
          content: Text('Booking created: $bookingId'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _submitWaitlist() async {
    setState(() => _saving = true);
    try {
      if (_shopId == null || _pickedSlots.isEmpty || _serviceIds.isEmpty) {
        throw Exception('Please complete the form.');
      }

      final waitId = await BookingBackend.instance.createWaitBooking(
        userId: 'U002',
        shopId: _shopId!,
        plateNumber: 'VAE6823',
        scheduleIds: _pickedSlots.map((s) => s.scheduleId).toList(),
        serviceIds: _serviceIds.toList(),
        othersText:
        _othersCtrl.text.trim().isEmpty ? null : _othersCtrl.text.trim(),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to waitlist: $waitId')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

extension _SB on StringBuffer {
  void writelnIf(bool cond, String text) {
    if (cond) writeln(text);
  }
}

class _Field extends StatelessWidget {
  final String label;
  final Widget child;
  const _Field({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

/// —— 时段范围选择：
/// includeFull=false → 仅显示“可预约”的 slot；
/// includeFull=true  → 显示所有 slot（含 FULL），用于等位。
class _SlotRangePicker extends StatefulWidget {
  final String? shopId;
  final DateTime day;
  final String? startId;
  final String? endId;
  final bool includeFull;
  final void Function(String? startId, String? endId, List<Schedule> slots)
  onChanged;

  const _SlotRangePicker({
    required this.shopId,
    required this.day,
    required this.startId,
    required this.endId,
    required this.onChanged,
    this.includeFull = false,
  });

  @override
  State<_SlotRangePicker> createState() => _SlotRangePickerState();
}

class _SlotRangePickerState extends State<_SlotRangePicker> {
  String? _startId;
  String? _endId;

  String? _lastStart;
  String? _lastEnd;
  String _lastSig = '';

  @override
  void initState() {
    super.initState();
    _startId = widget.startId;
    _endId = widget.endId;
  }

  @override
  void didUpdateWidget(covariant _SlotRangePicker old) {
    super.didUpdateWidget(old);
    if (old.shopId != widget.shopId ||
        old.day != widget.day ||
        old.includeFull != widget.includeFull) {
      _startId = null;
      _endId = null;
      _lastStart = null;
      _lastEnd = null;
      _lastSig = '';
    }
  }

  void _notifyPostFrame(String? s, String? e, List<Schedule> slots) {
    final sig =
    slots.isEmpty ? '' : '${slots.first.scheduleId}-${slots.last.scheduleId}';
    if (s == _lastStart && e == _lastEnd && sig == _lastSig) return;
    _lastStart = s;
    _lastEnd = e;
    _lastSig = sig;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onChanged(s, e, slots);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.shopId == null) return const Text('-');

    final dayStart =
    DateTime(widget.day.year, widget.day.month, widget.day.day);
    final nextDay = dayStart.add(const Duration(days: 1));
    final tf = DateFormat('HH:mm');

    return StreamBuilder<List<Schedule>>(
      stream: ScheduleViewBackend.instance.watchForShopInRange(
        shopId: widget.shopId!,
        startInclusive: dayStart,
        endExclusive: nextDay,
      ),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const SizedBox(
              height: 48,
              child: Center(child: CircularProgressIndicator()));
        }

        List<Schedule> slots = (snap.data ?? const <Schedule>[]).toList();
        // 预约模式只显示“可约”
        if (!widget.includeFull) {
          slots = slots
              .where((s) =>
          s.status.toLowerCase() == 'free' &&
              (s.totalCapacity - s.currentCapacity) > 0)
              .toList();
        }
        slots.sort((a, b) => a.startAt.compareTo(b.startAt));

        if (slots.isEmpty) {
          _notifyPostFrame(null, null, const []);
          return Text(widget.includeFull
              ? 'No time slots on this day.'
              : 'No available time slots (try the waitlist section below)');
        }

        final idx = {
          for (int i = 0; i < slots.length; i++) slots[i].scheduleId: i
        };

        if (_startId == null || !idx.containsKey(_startId)) {
          _startId = null;
          _endId = null;
        }

        List<DropdownMenuItem<String>> startItems = [
          for (final s in slots)
            DropdownMenuItem(
              value: s.scheduleId,
              child: Text(
                widget.includeFull
                    ? '${tf.format(s.startAt)}${(s.currentCapacity >= s.totalCapacity || s.status.toLowerCase() == 'full') ? " (FULL)" : ""}'
                    : tf.format(s.startAt),
              ),
            )
        ];

        List<DropdownMenuItem<String>> endItems = [];
        if (_startId != null) {
          final i0 = idx[_startId]!;
          endItems = [
            for (int j = i0; j < slots.length; j++)
              DropdownMenuItem(
                value: slots[j].scheduleId,
                child: Text(
                  widget.includeFull
                      ? '${tf.format(slots[j].endAt)}${(slots[j].currentCapacity >= slots[j].totalCapacity || slots[j].status.toLowerCase() == 'full') ? " (FULL)" : ""}'
                      : tf.format(slots[j].endAt),
                ),
              )
          ];
          final ok = _endId != null &&
              idx.containsKey(_endId) &&
              idx[_endId]! >= i0;
          if (!ok) _endId = slots[i0].scheduleId;
        } else {
          _endId = null;
        }

        _notifyPostFrame(_startId, _endId,
            _rangeSlots(slots, _startId, _endId));

        return Row(
          children: [
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _startId,
                hint: Text(widget.includeFull ? 'Start (incl. FULL)' : 'Start'),
                items: startItems,
                onChanged: (id) {
                  setState(() {
                    _startId = id;
                    _endId = null;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _endId,
                hint: const Text('End'),
                items: endItems,
                onChanged:
                (_startId == null) ? null : (id) => setState(() => _endId = id),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Schedule> _rangeSlots(
      List<Schedule> slots, String? startId, String? endId) {
    if (startId == null || endId == null) return const [];
    final i0 = slots.indexWhere((s) => s.scheduleId == startId);
    final i1 = slots.indexWhere((s) => s.scheduleId == endId);
    if (i0 < 0 || i1 < 0 || i1 < i0) return const [];
    return slots.sublist(i0, i1 + 1);
  }
}

/// —— 通用渲染辅助 ——
/// 组装服务名（含 Others 的备注）
String _serviceNames(
    List<String> ids, Map<String, String> svcMap, String othersText) {
  final list = <String>[];
  for (final id in ids) {
    final name = svcMap[id] ?? id;
    list.add(name);
  }
  final hasOthers = ids.any((id) =>
  (svcMap[id] ?? id).toLowerCase() == 'others' ||
      id.toUpperCase() == 'ST004');
  if (hasOthers && othersText.trim().isNotEmpty) {
    list.add('(${othersText.trim()})');
  }
  return list.join(', ');
}

/// —— 内嵌：当前用户的 pending 预订列表（带日期过滤 + 取消 + 店名/服务名）——
enum _DateFilter { all, today, next7, pick }

class _PendingBookingsSection extends StatefulWidget {
  final String userId;
  const _PendingBookingsSection({required this.userId});

  @override
  State<_PendingBookingsSection> createState() =>
      _PendingBookingsSectionState();
}

class _PendingBookingsSectionState extends State<_PendingBookingsSection> {
  final _canceling = <String>{};
  _DateFilter _filter = _DateFilter.all;
  DateTime? _picked; // Pick 模式下的日期

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d');
    final tf = DateFormat('HH:mm');
    final col = fs.FirebaseFirestore.instance.collection('Booking');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Your pending bookings',
                style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            DropdownButton<_DateFilter>(
              value: _filter,
              items: const [
                DropdownMenuItem(value: _DateFilter.all, child: Text('All')),
                DropdownMenuItem(
                    value: _DateFilter.today, child: Text('Today')),
                DropdownMenuItem(
                    value: _DateFilter.next7, child: Text('Next 7 days')),
                DropdownMenuItem(
                    value: _DateFilter.pick, child: Text('Pick date…')),
              ],
              onChanged: (f) async {
                if (f == null) return;
                if (f == _DateFilter.pick) {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                    context: context,
                    firstDate: now.subtract(const Duration(days: 365)),
                    lastDate: now.add(const Duration(days: 365)),
                    initialDate: _picked ?? now,
                  );
                  if (d != null) {
                    setState(() {
                      _filter = f;
                      _picked = DateTime(d.year, d.month, d.day);
                    });
                  }
                } else {
                  setState(() {
                    _filter = f;
                    _picked = null;
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 先把 Shop & Service 拉成 Map，后面渲染时可直接取
        StreamBuilder<List<Shop>>(
          stream: ShopBackend.instance.watchShops(),
          builder: (context, shopSnap) {
            final shopMap = {
              for (final s in (shopSnap.data ?? const <Shop>[]))
                s.shopId: s.location
            };
            return StreamBuilder<List<Service>>(
              stream: ServiceBackend.instance.watchServices(),
              builder: (context, svcSnap) {
                final svcMap = {
                  for (final s in (svcSnap.data ?? const <Service>[]))
                    s.serviceId: s.serviceType
                };

                return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
                  stream: col
                      .where('UserID', isEqualTo: widget.userId)
                      .where('Status', isEqualTo: BookingStatus.pending)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    // 拿到所有 pending → 客户端排序 & 过滤
                    final all = (snap.data?.docs ?? const []).toList();

                    bool sameDay(DateTime a, DateTime b) =>
                        a.year == b.year &&
                            a.month == b.month &&
                            a.day == b.day;

                    final today = DateTime.now();
                    final day0 =
                    DateTime(today.year, today.month, today.day);
                    final in7 = day0.add(const Duration(days: 7));

                    final filtered = all.where((doc) {
                      final start = (doc.data()['StartAt'] as fs.Timestamp?)
                          ?.toDate();
                      if (start == null) return false;
                      switch (_filter) {
                        case _DateFilter.all:
                          return true;
                        case _DateFilter.today:
                          return sameDay(start, day0);
                        case _DateFilter.next7:
                          final ds =
                          DateTime(start.year, start.month, start.day);
                          return !ds.isBefore(day0) && !ds.isAfter(in7);
                        case _DateFilter.pick:
                          if (_picked == null) return true;
                          return sameDay(start, _picked!);
                      }
                    }).toList()
                      ..sort((a, b) {
                        final ta = (a.data()['StartAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final tb = (b.data()['StartAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return ta.compareTo(tb);
                      });

                    if (filtered.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No pending bookings.'),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = filtered[i].data();
                        final id =
                            (d['BookingID'] as String?) ?? filtered[i].id;
                        final plate =
                            (d['VehiclePlate'] as String?) ?? '—';
                        final start =
                        (d['StartAt'] as fs.Timestamp?)?.toDate();
                        final end =
                        (d['EndAt'] as fs.Timestamp?)?.toDate();
                        final shopId = (d['ShopID'] as String?) ?? '';
                        final serviceIds =
                            (d['ServiceIDs'] as List?)?.cast<String>() ??
                                const <String>[];
                        final othersText =
                            (d['OthersText'] as String?) ?? '';

                        final when = (start != null)
                            ? '${df.format(start)} • ${tf.format(start)}–${end != null ? tf.format(end) : '--:--'}'
                            : '—';
                        final shopName = shopMap[shopId] ?? shopId;
                        final serviceNames =
                        _serviceNames(serviceIds, svcMap, othersText);

                        final busy = _canceling.contains(id);

                        return ListTile(
                          leading: const Icon(Icons.event_available),
                          title: Text('$id  •  $plate'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(when),
                              Text('Shop: $shopName'),
                              Text('Services: $serviceNames'),
                            ],
                          ),
                          trailing: TextButton.icon(
                            onPressed: busy
                                ? null
                                : () => _confirmCancel(context, id),
                            icon: busy
                                ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                                : const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, String bookingId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text('This will free up all related time slots.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, cancel')),
        ],
      ),
    ) ??
        false;
    if (!ok) return;

    setState(() => _canceling.add(bookingId));
    try {
      await BookingBackend.instance.cancelBooking(
        bookingId: bookingId,
        requestedBy: 'U002', // 与上方 userId 一致
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking cancelled.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancel failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _canceling.remove(bookingId));
    }
  }
}

/// —— 等位列表 ——
/// 可随时取消；系统会在有空位时自动晋升为 pending
class _WaitlistSection extends StatefulWidget {
  final String userId;
  const _WaitlistSection({required this.userId});

  @override
  State<_WaitlistSection> createState() => _WaitlistSectionState();
}

class _WaitlistSectionState extends State<_WaitlistSection> {
  final _canceling = <String>{};

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d');
    final tf = DateFormat('HH:mm');
    final col = fs.FirebaseFirestore.instance.collection('Booking');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your waitlist', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        // Shop & Service 映射
        StreamBuilder<List<Shop>>(
          stream: ShopBackend.instance.watchShops(),
          builder: (context, shopSnap) {
            final shopMap = {
              for (final s in (shopSnap.data ?? const <Shop>[]))
                s.shopId: s.location
            };
            return StreamBuilder<List<Service>>(
              stream: ServiceBackend.instance.watchServices(),
              builder: (context, svcSnap) {
                final svcMap = {
                  for (final s in (svcSnap.data ?? const <Service>[]))
                    s.serviceId: s.serviceType
                };

                return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
                  stream: col
                      .where('UserID', isEqualTo: widget.userId)
                      .where('Status', isEqualTo: BookingStatus.wait)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final docs = (snap.data?.docs ?? const [])
                      ..sort((a, b) {
                        final ta = (a.data()['CreatedAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final tb = (b.data()['CreatedAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return ta.compareTo(tb); // 先加入的排前
                      });

                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No items on the waitlist.'),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = docs[i].data();
                        final id = (d['BookingID'] as String?) ?? docs[i].id;
                        final plate =
                            (d['VehiclePlate'] as String?) ?? '—';
                        final start =
                        (d['StartAt'] as fs.Timestamp?)?.toDate();
                        final end =
                        (d['EndAt'] as fs.Timestamp?)?.toDate();
                        final shopId = (d['ShopID'] as String?) ?? '';
                        final serviceIds =
                            (d['ServiceIDs'] as List?)?.cast<String>() ??
                                const <String>[];
                        final othersText =
                            (d['OthersText'] as String?) ?? '';

                        final when = (start != null)
                            ? '${df.format(start)} • ${tf.format(start)}–${end != null ? tf.format(end) : '--:--'}'
                            : '—';
                        final shopName = shopMap[shopId] ?? shopId;
                        final serviceNames =
                        _serviceNames(serviceIds, svcMap, othersText);

                        final busy = _canceling.contains(id);

                        return ListTile(
                          leading: const Icon(Icons.hourglass_bottom),
                          title: Text('$id  •  $plate'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(when),
                              Text('Shop: $shopName'),
                              Text('Services: $serviceNames'),
                            ],
                          ),
                          trailing: TextButton.icon(
                            onPressed: busy ? null : () => _cancelWait(id),
                            icon: busy
                                ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            )
                                : const Icon(Icons.cancel_outlined),
                            label: const Text('Cancel'),
                            style: TextButton.styleFrom(
                                foregroundColor: Colors.red),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }

  Future<void> _cancelWait(String bookingId) async {
    setState(() => _canceling.add(bookingId));
    try {
      await BookingBackend.instance.cancelBooking(
        bookingId: bookingId,
        requestedBy: 'U002',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Removed from waitlist.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cancel failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _canceling.remove(bookingId));
    }
  }
}

/// —— 内嵌：当前用户的 expired 预订列表（实时，只读展示；含店名/服务名；客户端排序避免索引）——
class _ExpiredBookingsSection extends StatelessWidget {
  final String userId;
  const _ExpiredBookingsSection({required this.userId});

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('EEE, MMM d');
    final tf = DateFormat('HH:mm');
    final col = fs.FirebaseFirestore.instance.collection('Booking');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Expired bookings',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),

        // 先取 Shop & Service 映射，再渲染 Expired 列表
        StreamBuilder<List<Shop>>(
          stream: ShopBackend.instance.watchShops(),
          builder: (context, shopSnap) {
            final shopMap = {
              for (final s in (shopSnap.data ?? const <Shop>[]))
                s.shopId: s.location
            };
            return StreamBuilder<List<Service>>(
              stream: ServiceBackend.instance.watchServices(),
              builder: (context, svcSnap) {
                final svcMap = {
                  for (final s in (svcSnap.data ?? const <Service>[]))
                    s.serviceId: s.serviceType
                };

                return StreamBuilder<fs.QuerySnapshot<Map<String, dynamic>>>(
                  stream: col
                      .where('UserID', isEqualTo: userId)
                      .where('Status', isEqualTo: BookingStatus.expired)
                  // 不用 orderBy，避免索引；客户端降序排
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final docs = (snap.data?.docs ?? const [])
                      ..sort((a, b) {
                        final ta = (a.data()['StartAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        final tb = (b.data()['StartAt'] as fs.Timestamp?)
                            ?.toDate() ??
                            DateTime.fromMillisecondsSinceEpoch(0);
                        return tb.compareTo(ta); // 降序
                      });

                    if (docs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('No expired bookings.'),
                      );
                    }

                    return ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = docs[i].data();
                        final id = (d['BookingID'] as String?) ?? docs[i].id;
                        final plate =
                            (d['VehiclePlate'] as String?) ?? '—';
                        final start =
                        (d['StartAt'] as fs.Timestamp?)?.toDate();
                        final end =
                        (d['EndAt'] as fs.Timestamp?)?.toDate();
                        final shopId = (d['ShopID'] as String?) ?? '';
                        final serviceIds =
                            (d['ServiceIDs'] as List?)?.cast<String>() ??
                                const <String>[];
                        final othersText =
                            (d['OthersText'] as String?) ?? '';

                        final when = (start != null)
                            ? '${df.format(start)} • ${tf.format(start)}–${end != null ? tf.format(end) : '--:--'}'
                            : '—';
                        final shopName = shopMap[shopId] ?? shopId;
                        final serviceNames =
                        _serviceNames(serviceIds, svcMap, othersText);

                        return ListTile(
                          leading: const Icon(Icons.history,
                              color: Colors.redAccent),
                          title: Text('$id  •  $plate'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(when),
                              Text('Shop: $shopName'),
                              Text('Services: $serviceNames'),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            );
          },
        ),
      ],
    );
  }
}

/// 显示当前本地日期时间（每秒刷新）
class _NowClock extends StatelessWidget {
  const _NowClock();

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('yyyy-MM-dd (EEE) HH:mm:ss');

    return StreamBuilder<DateTime>(
      stream: Stream<DateTime>.periodic(
        const Duration(seconds: 1),
            (_) => DateTime.now(),
      ),
      builder: (context, snap) {
        final now = snap.data ?? DateTime.now();
        final local = df.format(now);
        final tz = now.timeZoneName;

        return Row(
          children: [
            const Icon(Icons.access_time, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Now: $local  ($tz)',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: Colors.grey),
            ),
          ],
        );
      },
    );
  }
}
