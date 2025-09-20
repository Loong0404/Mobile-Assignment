// lib/frontend/billing_pages.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../backend/billing.dart';
import '../backend/payment.dart';

class BillingListPage extends StatelessWidget {
  const BillingListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _RequireLogin();

    return Scaffold(
      appBar: AppBar(title: const Text('Invoices')),
      body: StreamBuilder<List<InvoiceModel>>(
        stream: BillingService().watchUserInvoicesSafe(uid),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Error: ${snap.error}',
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final invoices = snap.data!;
          if (invoices.isEmpty) return const Center(child: Text('No invoices yet.'));

          return ListView.separated(
            itemCount: invoices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final inv = invoices[i];
              final paid = inv.status.toLowerCase() == 'paid';
              final color = paid ? Colors.green : Colors.orange;
              return ListTile(
                title: Text('RM ${inv.amount.toStringAsFixed(2)} • ${inv.plateNumber}'),
                subtitle: Text(_ymd(inv.date)),
                trailing: Chip(
                  label: Text(inv.status),
                  backgroundColor: color.withOpacity(.1),
                  labelStyle: TextStyle(color: color),
                  side: BorderSide(color: color),
                ),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => InvoiceDetailPage(invoiceID: inv.invoiceID)),
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

class InvoiceDetailPage extends StatefulWidget {
  final String invoiceID;
  const InvoiceDetailPage({super.key, required this.invoiceID});

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  InvoiceModel? inv;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await BillingService().getInvoice(widget.invoiceID);
    if (!mounted) return;
    setState(() {
      inv = data;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const _RequireLogin();

    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (inv == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Invoice')),
        body: const Center(child: Text('Invoice not found')),
      );
    }

    final i = inv!;
    final paid = i.status.toLowerCase() == 'paid';
    final color = paid ? Colors.green : Colors.orange;

    return Scaffold(
      appBar: AppBar(title: Text('Invoice ${i.invoiceID}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _kv('Amount', 'RM ${i.amount.toStringAsFixed(2)}'),
                _kv('Date', _ymd(i.date)),
                _kv('Booking ID', i.bookingID),
                _kv('Plate', i.plateNumber),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: Text(i.status),
                    backgroundColor: color.withOpacity(.1),
                    labelStyle: TextStyle(color: color),
                    side: BorderSide(color: color),
                  ),
                ),
                const Spacer(),
                if (!paid)
                  FilledButton(
                    onPressed: () async {
                      final ok = await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PaymentPage(invoice: i)),
                      );
                      if (ok == true && mounted) await _load();
                    },
                    child: const Text('Proceed to Payment'),
                  ),
              ],
            ),
          ),
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

  static String _ymd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class PaymentPage extends StatefulWidget {
  final InvoiceModel invoice;
  const PaymentPage({super.key, required this.invoice});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String method = 'FPX';
  bool paying = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final i = widget.invoice;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
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
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'Card', label: Text('Card')),
                ButtonSegment(value: 'FPX', label: Text('FPX')),
                ButtonSegment(value: 'eWallet', label: Text('eWallet')),
              ],
              selected: {method},
              onSelectionChanged: (s) => setState(() => method = s.first),
            ),
            const Spacer(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: paying ? null : _pay,
              child: paying
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Pay RM ${i.amount.toStringAsFixed(2)}'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pay() async {
    setState(() {
      paying = true;
      error = null;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Please sign in');

      // Mark invoice paid, then create the payment record
      await BillingService().markPaid(widget.invoice.invoiceID);
      await PaymentService().createPayment(
        invoiceID: widget.invoice.invoiceID,
        userId: uid,
        amount: widget.invoice.amount,
        paymentTime: TimeOfDay.now().format(context),
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => paying = false);
    }
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

  static String _ymd(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class _RequireLogin extends StatelessWidget {
  const _RequireLogin({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Please sign in to continue.')),
    );
  }
}
