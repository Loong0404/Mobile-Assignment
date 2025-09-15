import 'package:flutter/material.dart';
import '../backend/billing.dart';

/// TODO: Replace this with your real auth session / Firebase user id.
/// For now we keep a simple demo user id so the pages work out of the box.
String? get currentUserId => 'u1';

// ========== Billing List ==========
class BillingListPage extends StatelessWidget {
  const BillingListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = currentUserId;
    if (userId == null) {
      // Safety: if accessed without login
      return const _RequireLoginView();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: StreamBuilder<List<Bill>>(
        stream: BillingBackend.instance.watchBillsForUser(userId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final bills = snap.data!;
          if (bills.isEmpty) {
            return const Center(child: Text('No bills yet.'));
          }
          return ListView.separated(
            itemCount: bills.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final b = bills[i];
              final statusColor =
                  b.status == BillStatus.paid ? Colors.green : Colors.orange;
              return ListTile(
                title: Text('Plate: ${b.plate}'),
                subtitle: Text(
                  'Created: ${_ymd(b.createdAt)} • Amount: RM ${b.amount.toStringAsFixed(2)}',
                ),
                trailing: Chip(
                  label: Text(b.status == BillStatus.paid ? 'Paid' : 'Pending'),
                  backgroundColor: statusColor.withOpacity(.1),
                  side: BorderSide(color: statusColor),
                  labelStyle: TextStyle(color: statusColor),
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => BillDetailPage(billId: b.id),
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
}

// ========== Bill Detail ==========
class BillDetailPage extends StatefulWidget {
  final String billId;
  const BillDetailPage({super.key, required this.billId});

  @override
  State<BillDetailPage> createState() => _BillDetailPageState();
}

class _BillDetailPageState extends State<BillDetailPage> {
  Bill? bill;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final b = await BillingBackend.instance.getBill(widget.billId);
    setState(() {
      bill = b;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill Detail')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (bill == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Bill Detail')),
        body: const Center(child: Text('Bill not found')),
      );
    }
    final b = bill!;
    final statusColor =
        b.status == BillStatus.paid ? Colors.green : Colors.orange;

    return Scaffold(
      appBar: AppBar(title: const Text('Bill Detail')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row('Bill ID', b.id),
                _row('Vehicle Plate', b.plate),
                _row('Date', _ymd(b.createdAt)),
                _row('Amount', 'RM ${b.amount.toStringAsFixed(2)}'),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Status',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    Chip(
                      label:
                          Text(b.status == BillStatus.paid ? 'Paid' : 'Pending'),
                      backgroundColor: statusColor.withOpacity(.1),
                      side: BorderSide(color: statusColor),
                      labelStyle: TextStyle(color: statusColor),
                    ),
                  ],
                ),
                const Spacer(),
                FilledButton(
                  onPressed: b.status == BillStatus.paid
                      ? null
                      : () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PaymentPage(bill: b),
                            ),
                          );
                          if (updated == true) {
                            // refresh
                            _load();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Payment successful'),
                              ),
                            );
                          }
                        },
                  child: const Text('Proceed to Payment'),
                )
              ],
            ),
          ),
        ),
      ),
    );
  }

  static Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  static String _ymd(DateTime dt) =>
      '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ========== Payment Page ==========
class PaymentPage extends StatefulWidget {
  final Bill bill;
  const PaymentPage({super.key, required this.bill});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  String method = 'Card';
  bool paying = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    final bill = widget.bill;
    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _summaryCard(bill),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Payment Method',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const SizedBox(height: 8),
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
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator())
                  : Text('Pay RM ${bill.amount.toStringAsFixed(2)}'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(Bill bill) {
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

  Future<void> _pay() async {
    setState(() {
      paying = true;
      error = null;
    });
    try {
      final userId = currentUserId;
      if (userId == null) {
        throw Exception('Please sign in to pay.');
      }
      await BillingBackend.instance.payBill(
        billId: widget.bill.id,
        userId: userId,
        method: method,
      );
      if (mounted) Navigator.pop(context, true); // return success
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => paying = false);
    }
  }
}

class _RequireLoginView extends StatelessWidget {
  const _RequireLoginView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing')),
      body: const Center(
        child: Text('Please sign in to view your bills.'),
      ),
    );
  }
}
