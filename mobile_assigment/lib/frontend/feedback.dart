import 'package:flutter/material.dart';
import '../backend/billing.dart';

/// Use your real session here (Firebase UID later). Demo user:
String? get currentUserId => 'u1';

class FeedbackListPage extends StatelessWidget {
  const FeedbackListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = currentUserId;
    if (uid == null) {
      return const _RequireLogin();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: StreamBuilder<List<Bill>>(
        initialData: const [],
        stream: BillingBackend.instance.watchBillsForUser(uid),
        builder: (context, snap) {
          final bills = (snap.data ?? [])
              .where((b) => b.status == BillStatus.paid)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

          if (snap.connectionState == ConnectionState.waiting && bills.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (bills.isEmpty) {
            return const Center(child: Text('No paid bills yet.'));
          }

          return ListView.separated(
            itemCount: bills.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final bill = bills[i];
              return FutureBuilder<FeedbackEntry?>(
                future: BillingBackend.instance.getFeedbackForBill(
                  billId: bill.id,
                  userId: uid,
                ),
                builder: (context, fbSnap) {
                  final fb = fbSnap.data;
                  return ListTile(
                    title: Text('Plate: ${bill.plate} • RM ${bill.amount.toStringAsFixed(2)}'),
                    subtitle: fb == null
                        ? const Text('No feedback yet')
                        : Text('${_stars(fb.rating)}  •  ${_ymd(fb.createdAt)}\n${fb.comment}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                    isThreeLine: fb != null,
                    trailing: TextButton(
                      child: Text(fb == null ? 'Leave feedback' : 'Edit'),
                      onPressed: () async {
                        final changed = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FeedbackFormPage(bill: bill, existing: fb),
                          ),
                        );
                        if (changed == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Feedback saved')),
                          );
                        }
                      },
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  static String _ymd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  static String _stars(int rating) => '★' * rating + '☆' * (5 - rating);
}

class FeedbackFormPage extends StatefulWidget {
  final Bill bill;
  final FeedbackEntry? existing;
  const FeedbackFormPage({super.key, required this.bill, this.existing});

  @override
  State<FeedbackFormPage> createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  int rating = 5;
  final controller = TextEditingController();
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      rating = widget.existing!.rating;
      controller.text = widget.existing!.comment;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Scaffold(
      appBar: AppBar(title: const Text('Leave Feedback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _billSummary(bill),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Rating', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (i) {
                final starIndex = i + 1;
                final filled = starIndex <= rating;
                return IconButton(
                  icon: Icon(filled ? Icons.star : Icons.star_border),
                  onPressed: () => setState(() => rating = starIndex),
                  tooltip: '$starIndex',
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Comment',
                hintText: 'Tell us about your payment experience…',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            if (error != null) Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
            FilledButton.icon(
              icon: saving ? const SizedBox(
                width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2),
              ) : const Icon(Icons.save),
              label: Text(saving ? 'Saving...' : 'Submit'),
              onPressed: saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _billSummary(Bill bill) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _kv('Bill ID', bill.id),
            _kv('Plate', bill.plate),
            _kv('Date',
                '${bill.createdAt.year}-${bill.createdAt.month.toString().padLeft(2, '0')}-${bill.createdAt.day.toString().padLeft(2, '0')}'),
            _kv('Amount', 'RM ${bill.amount.toStringAsFixed(2)}'),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                label: const Text('Paid'),
                side: const BorderSide(color: Colors.green),
                backgroundColor: Colors.green.withOpacity(.1),
                labelStyle: const TextStyle(color: Colors.green),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
        Flexible(child: Text(v, textAlign: TextAlign.right)),
      ],
    ),
  );

  Future<void> _submit() async {
    setState(() { saving = true; error = null; });
    try {
      final uid = currentUserId;
      if (uid == null) throw Exception('Please sign in.');

      await BillingBackend.instance.submitFeedback(
        billId: widget.bill.id,
        userId: uid,
        rating: rating,
        comment: controller.text.trim(),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }
}

class _RequireLogin extends StatelessWidget {
  const _RequireLogin();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Please sign in to use feedback.')),
    );
  }
}
