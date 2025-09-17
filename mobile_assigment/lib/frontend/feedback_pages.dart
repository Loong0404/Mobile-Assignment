import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../backend/billing.dart';
import '../backend/feedback.dart';

/// Minimal overview page so the `/feedback` route works.
/// Replace with your own list/analytics later.
class FeedbackListPage extends StatelessWidget {
  const FeedbackListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('My Feedbacks')),
      body: StreamBuilder(
        stream: FeedbackService()
            .watchFeedbacks('*', uid) // you can change to show all by user
            .map((list) => list),      // simple passthrough
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return const Center(child: Text('No feedback yet.'));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (_, i) {
              final f = items[i];
              return ListTile(
                title: Text('Invoice: ${f.invoiceID}  •  ${f.rating} ★'),
                subtitle: Text(f.comment),
                trailing: Text(
                  '${f.date.year}-${f.date.month.toString().padLeft(2, '0')}-${f.date.day.toString().padLeft(2, '0')}',
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// The per-invoice feedback form page, opened from InvoiceDetailPage.
class FeedbackFormPage extends StatefulWidget {
  final InvoiceModel invoice;
  const FeedbackFormPage({super.key, required this.invoice});

  @override
  State<FeedbackFormPage> createState() => _FeedbackFormPageState();
}

class _FeedbackFormPageState extends State<FeedbackFormPage> {
  int rating = 5;
  final commentCtrl = TextEditingController();
  bool saving = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _invoiceSummary(i),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Rating', style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
            Row(
              children: List.generate(5, (idx) {
                final star = idx + 1;
                final filled = star <= rating;
                return IconButton(
                  icon: Icon(filled ? Icons.star : Icons.star_border),
                  onPressed: () => setState(() => rating = star),
                );
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              minLines: 3, maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Comment',
                hintText: 'Tell us about your experience…',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton.icon(
              icon: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(saving ? 'Saving...' : 'Submit'),
              onPressed: saving ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    setState(() { saving = true; error = null; });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Please sign in');
      await FeedbackService().leaveFeedback(
        invoiceID: widget.invoice.invoiceID,
        userId: uid,
        rating: rating,
        comment: commentCtrl.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _invoiceSummary(InvoiceModel i) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _kv('Invoice ID', i.invoiceID),
              _kv('Plate', i.plateNumber),
              _kv('Date', _ymd(i.date)),
              _kv('Amount', 'RM ${i.amount.toStringAsFixed(2)}'),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Chip(
                  label: const Text('paid'),
                  backgroundColor: Colors.green.withOpacity(.1),
                  labelStyle: const TextStyle(color: Colors.green),
                  side: const BorderSide(color: Colors.green),
                ),
              ),
            ],
          ),
        ),
      );

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

  static String _ymd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}
