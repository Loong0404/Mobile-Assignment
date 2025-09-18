import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../backend/billing.dart';
import '../backend/feedback.dart';

class FeedbackListPage extends StatelessWidget {
  const FeedbackListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Please sign in.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Feedback')),
      body: StreamBuilder<List<InvoiceModel>>(
        stream: BillingService().watchPaidInvoicesSafe(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (!snap.hasData)
            return const Center(child: CircularProgressIndicator());

          final invoices = snap.data!;
          if (invoices.isEmpty)
            return const Center(child: Text('No paid bills yet.'));

          return ListView.separated(
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final inv = invoices[i];
              return ListTile(
                title: Text(
                  'Invoice ${inv.invoiceID} • RM ${inv.amount.toStringAsFixed(2)}',
                ),
                subtitle: Text('${inv.plateNumber} • ${_ymd(inv.date)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FeedbackDetailPage(invoice: inv),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  static String _ymd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class FeedbackDetailPage extends StatefulWidget {
  final InvoiceModel invoice;
  const FeedbackDetailPage({super.key, required this.invoice});

  @override
  State<FeedbackDetailPage> createState() => _FeedbackDetailPageState();
}

class _FeedbackDetailPageState extends State<FeedbackDetailPage> {
  final svc = FeedbackService();
  int rating = 5;
  final commentCtrl = TextEditingController();
  String? existingPhotoUrl;
  String? uploadedPhotoUrl; // new photo uploaded in this session
  bool loading = true;
  bool saving = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final fb = await svc.getMyFeedback(widget.invoice.invoiceID, uid);
    if (!mounted) return;
    setState(() {
      if (fb != null) {
        rating = fb.rating;
        commentCtrl.text = fb.comment;
        existingPhotoUrl = fb.photoUrl;
      }
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;

    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Feedback')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final hasExisting = commentCtrl.text.isNotEmpty || existingPhotoUrl != null;

    return Scaffold(
      appBar: AppBar(title: Text('Invoice ${i.invoiceID}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _invoiceSummary(i),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Your Feedback',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (!hasExisting)
              const Padding(
                padding: EdgeInsets.only(top: 6, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('No feedback yet.'),
                ),
              ),
            const SizedBox(height: 8),
            _ratingRow(),
            const SizedBox(height: 8),
            TextField(
              controller: commentCtrl,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: 'Comment',
                hintText: 'Tell us about your experience…',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            _photoSection(),
            const Spacer(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton.icon(
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(saving ? 'Saving...' : 'Save Feedback'),
              onPressed: saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _ratingRow() => Row(
    children: List.generate(5, (idx) {
      final star = idx + 1;
      final filled = star <= rating;
      return IconButton(
        icon: Icon(filled ? Icons.star : Icons.star_border),
        onPressed: () => setState(() => rating = star),
      );
    }),
  );

  Widget _photoSection() {
    final previewUrl = uploadedPhotoUrl ?? existingPhotoUrl;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Photo (optional)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (previewUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              previewUrl,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        if (previewUrl == null)
          Container(
            height: 160,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: const Text('No photo'),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_camera),
              label: const Text('Take photo'),
              onPressed: () => _pickAndUpload(ImageSource.camera),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from gallery'),
              onPressed: () => _pickAndUpload(ImageSource.gallery),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickAndUpload(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: source, maxWidth: 1600);
      if (xfile == null) return;

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final path =
          'feedback_photos/$uid/${widget.invoice.invoiceID}-${DateTime.now().millisecondsSinceEpoch}.jpg';

      final file = File(xfile.path);
      final task = await FirebaseStorage.instance.ref(path).putFile(file);
      final url = await task.ref.getDownloadURL();

      if (!mounted) return;
      setState(() {
        uploadedPhotoUrl = url;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Photo uploaded')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    }
  }

  Future<void> _save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Please sign in');

      await svc.upsertFeedback(
        invoiceID: widget.invoice.invoiceID,
        userId: uid,
        rating: rating,
        comment: commentCtrl.text.trim(),
        photoUrl: uploadedPhotoUrl ?? existingPhotoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Feedback saved')));
        Navigator.pop(context, true);
      }
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
