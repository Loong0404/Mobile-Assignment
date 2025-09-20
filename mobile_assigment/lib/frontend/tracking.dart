import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../backend/tracking.dart';
import '../backend/tracking_service.dart';
import 'stage_details_page.dart';

class TrackingPage extends StatefulWidget {
  const TrackingPage({super.key});

  @override
  State<TrackingPage> createState() => _TrackingPageState();
}

class _TrackingPageState extends State<TrackingPage> {
  Stream<List<ServiceTracking>>? _stream;
  final List<ServiceTracking> _historyTrackings = [];
  String _historyFilter =
      'all'; // 'all' | 'completed' | 'cancelled' | 'expired'

  @override
  void initState() {
    super.initState();
    // Seed technicians if needed and initialize trackings for this user, then stream
    Future(() async {
      await TrackingService.instance.seedTechniciansIfEmpty();
      await TrackingService.instance.initTrackingsForCurrentUser();
      await TrackingService.instance.startLiveSync();
      setState(() {
        _stream = TrackingService.instance.streamTrackingsForCurrentUser();
      });
    });
  }

  @override
  void dispose() {
    TrackingService.instance.stopLiveSync();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Service Tracking"),
        backgroundColor: WmsApp.grabGreen,
        foregroundColor: Colors.white,
      ),
      body: _stream == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<List<ServiceTracking>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final items = snapshot.data ?? [];
                if (items.isEmpty && _historyTrackings.isEmpty) {
                  return _buildEmptyState();
                }

                bool isTerminated(ServiceTracking t) {
                  final s = t.currentStatus.toLowerCase();
                  return s == 'cancelled' || s == 'expired';
                }

                bool isCompleted(ServiceTracking t) =>
                    t.currentStatus.toLowerCase() == 'completed';

                // Treat Ready for Collection as active/current, not history
                // Completed should be shown in History but remain tappable
                final current = items
                    .where((t) => !isTerminated(t) && !isCompleted(t))
                    .toList();
                // Build history then filter by selected status; sort newest first
                List<ServiceTracking> history = [
                  ...items.where((t) => isTerminated(t) || isCompleted(t)),
                  ..._historyTrackings,
                ];
                if (_historyFilter != 'all') {
                  final f = _historyFilter;
                  history =
                      history
                          .where((t) => t.currentStatus.toLowerCase() == f)
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                } else {
                  final completed =
                      history
                          .where(
                            (t) => t.currentStatus.toLowerCase() == 'completed',
                          )
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  final cancelled =
                      history
                          .where(
                            (t) => t.currentStatus.toLowerCase() == 'cancelled',
                          )
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  final expired =
                      history
                          .where(
                            (t) => t.currentStatus.toLowerCase() == 'expired',
                          )
                          .toList()
                        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
                  history = [...completed, ...cancelled, ...expired];
                }
                return _buildTrackingList(current: current, history: history);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            "No tracking information available",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Book a service to start tracking",
            style: TextStyle(color: Colors.grey[500]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
            },
            icon: const Icon(Icons.add),
            label: const Text("Book a Service"),
            style: ElevatedButton.styleFrom(minimumSize: const Size(200, 48)),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingList({
    required List<ServiceTracking> current,
    required List<ServiceTracking> history,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (current.isNotEmpty) ...[
          Text(
            "Current Bookings",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: WmsApp.grabDark,
            ),
          ),
          const SizedBox(height: 12),
          ...current.map(
            (tracking) => _buildTrackingCard(tracking, isHistory: false),
          ),
          const SizedBox(height: 24),
        ],

        if (history.isNotEmpty) ...[
          Row(
            children: [
              Text(
                "Tracking History",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: WmsApp.grabDark,
                ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: 'Filter history',
                icon: const Icon(Icons.filter_list),
                onSelected: (value) => setState(() {
                  _historyFilter =
                      value; // 'all' | 'completed' | 'cancelled' | 'expired'
                }),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'all', child: Text('All')),
                  PopupMenuItem(value: 'completed', child: Text('Completed')),
                  PopupMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  PopupMenuItem(value: 'expired', child: Text('Expired')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...history.map(
            (tracking) => _buildTrackingCard(tracking, isHistory: true),
          ),
        ],
      ],
    );
  }

  // Helper method to calculate the progress value based on current status
  double _calculateProgressValue(String currentStatus) {
    // Now that Ready for Collection is at the top of the list, we need custom progress logic

    // Do not mark Ready for Collection as completed automatically

    // For other statuses, we need to calculate based on service flow, not list order
    final serviceFlow = [
      TrackingBackend.vehicleReceived,
      TrackingBackend.initialDiagnosis,
      TrackingBackend.inInspection,
      TrackingBackend.partsAwaiting,
      TrackingBackend.inRepair,
      TrackingBackend.qualityCheck,
      TrackingBackend.finalTesting,
      TrackingBackend.readyForCollection,
    ];

    if (currentStatus.toLowerCase() == 'completed') return 1.0;

    final currentIndex = serviceFlow.indexOf(currentStatus);
    if (currentIndex == -1) return 0.0;

    return (currentIndex + 1) / serviceFlow.length;
  }

  Widget _buildTrackingCard(
    ServiceTracking tracking, {
    required bool isHistory,
  }) {
    final dateFormat = DateFormat("MMM dd, yyyy");
    final isTerminated = _isTerminatedStatus(tracking.currentStatus);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: isTerminated
            ? null
            : () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        TrackingDetailPage(tracking: tracking),
                  ),
                );
              },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: (isHistory || isTerminated)
                          ? Colors.grey[200]
                          : TrackingBackend.getStatusColor(
                              tracking.currentStatus,
                            ).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      TrackingBackend.getStatusIcon(tracking.currentStatus),
                      color: (isHistory || isTerminated)
                          ? Colors.grey[600]
                          : TrackingBackend.getStatusColor(
                              tracking.currentStatus,
                            ),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                "Booking ${tracking.bookingId}",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _statusBadge(
                              isHistory: isHistory,
                              status: tracking.currentStatus,
                            ),
                          ],
                        ),
                        // Show service info when available
                        if (((tracking.serviceIds ?? const []).isNotEmpty) ||
                            (tracking.serviceId ?? '').isNotEmpty ||
                            (tracking.serviceType ?? '').isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if ((tracking.serviceIds ?? const []).isNotEmpty)
                                ...List.generate(tracking.serviceIds!.length, (
                                  i,
                                ) {
                                  final id = tracking.serviceIds![i];
                                  final type =
                                      (tracking.serviceTypes != null &&
                                          i < tracking.serviceTypes!.length)
                                      ? tracking.serviceTypes![i]
                                      : null;
                                  return _ServiceChip(id: id, type: type);
                                })
                              else
                                _ServiceChip(
                                  id: tracking.serviceId,
                                  type: tracking.serviceType,
                                ),
                            ],
                          ),
                        ],
                        if (tracking.plateNumber != null &&
                            tracking.plateNumber!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.directions_car,
                                size: 14,
                                color: Colors.grey[700],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                tracking.plateNumber!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          "Updated: ${dateFormat.format(tracking.updatedAt)}",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              StreamBuilder<Technician?>(
                stream: TrackingService.instance.streamTechnician(
                  tracking.technicianId,
                ),
                builder: (context, snap) {
                  final tech = snap.data ?? tracking.technician;
                  final name =
                      tech?.name ?? 'Technician ${tracking.technicianId}';
                  return Text(
                    "Technician: $name",
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  );
                },
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: isTerminated
                    ? 0.0
                    : _calculateProgressValue(tracking.currentStatus),
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation<Color>(
                  isTerminated ? Colors.grey : WmsApp.grabGreen,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 4),
              if (!isTerminated)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      "View Details",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: WmsApp.grabGreen,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: WmsApp.grabGreen,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isTerminatedStatus(String status) {
    final s = status.toLowerCase();
    return s == 'cancelled' || s == 'expired';
  }

  Widget _ServiceChip({String? id, String? type}) {
    final label = [
      if ((id ?? '').isNotEmpty) id!,
      if ((type ?? '').isNotEmpty) type!,
    ].join(' • ');
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blueGrey.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.miscellaneous_services,
            size: 12,
            color: Colors.blueGrey,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.blueGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge({required bool isHistory, required String status}) {
    final isTerminated = _isTerminatedStatus(status);
    final color = isTerminated
        ? Colors.grey[700]!
        : TrackingBackend.getStatusColor(status);
    final bg = isTerminated
        ? Colors.grey[100]!
        : TrackingBackend.getStatusColor(status).withOpacity(0.1);
    final border = isTerminated
        ? Colors.grey[400]!
        : TrackingBackend.getStatusColor(status).withOpacity(0.5);
    return Container(
      margin: const EdgeInsets.only(left: 8),
      constraints: const BoxConstraints(maxWidth: 140),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Text(
        isTerminated ? status : status,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}

class TrackingDetailPage extends StatefulWidget {
  final ServiceTracking tracking;

  const TrackingDetailPage({super.key, required this.tracking});

  @override
  State<TrackingDetailPage> createState() => _TrackingDetailPageState();
}

class _TrackingDetailPageState extends State<TrackingDetailPage> {
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _selectedStatus = null;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: FutureBuilder<String?>(
          future: TrackingService.instance.fetchPlateNumberForBooking(
            widget.tracking.bookingId,
          ),
          builder: (context, snap) {
            final plate = snap.data;
            final title = (plate != null && plate.trim().isNotEmpty)
                ? "Booking ${widget.tracking.bookingId} • ${plate.trim()}"
                : "Booking ${widget.tracking.bookingId}";
            return Text(title);
          },
        ),
        backgroundColor: WmsApp.grabGreen,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildHorizontalStepper(),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Plate is now shown in the AppBar title
                    _buildSimplifiedVerticalTimeline(),
                    // Removed duplicate stage details section
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // New simplified vertical timeline with inline details
  Widget _buildSimplifiedVerticalTimeline() {
    // Use the service flow order rather than allStatuses for display
    final serviceFlow = [
      TrackingBackend.vehicleReceived,
      TrackingBackend.initialDiagnosis,
      TrackingBackend.inInspection,
      TrackingBackend.partsAwaiting,
      TrackingBackend.inRepair,
      TrackingBackend.qualityCheck,
      TrackingBackend.finalTesting,
      TrackingBackend.readyForCollection,
    ];

    final currentStatus = widget.tracking.currentStatus;
    final bool markAllComplete = currentStatus.toLowerCase() == 'completed';
    final currentFlowIndex = markAllComplete
        ? serviceFlow.length - 1
        : serviceFlow.indexOf(currentStatus);

    // Ready for Collection should be shown as current/active, not complete
    // Completed should mark all stages as complete
    final isComplete = markAllComplete;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Service Stages",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: WmsApp.grabDark,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(serviceFlow.length, (index) {
            final status = serviceFlow[index];
            final isPast = index < currentFlowIndex || isComplete;
            final isCurrent = index == currentFlowIndex && !isComplete;
            final isSelected = status == _selectedStatus;

            // Color scheme based on status
            final statusColor = isPast
                ? Colors.grey[600]
                : isCurrent
                ? WmsApp.grabGreen
                : Colors.grey[400];

            // Get the status update if available
            final statusUpdate = widget.tracking.statusUpdates[status];
            final hasUpdate = statusUpdate != null;
            final canSelect =
                isPast ||
                isCurrent; // Only allow selection of past or current stages

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stage timeline item
                GestureDetector(
                  onTap: canSelect
                      ? () => _showStageDetailsPage(
                          status,
                          hasUpdate ? statusUpdate : null,
                        )
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Timeline indicator
                        Column(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: statusColor,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.grey.withOpacity(0.3),
                                        blurRadius: 4,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Icon(
                                      TrackingBackend.getStatusIcon(status),
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                                if (isPast)
                                  Positioned(
                                    right: -2,
                                    bottom: -2,
                                    child: Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.green,
                                          width: 1,
                                        ),
                                      ),
                                      child: Center(
                                        child: Icon(
                                          Icons.check,
                                          color: Colors.green,
                                          size: 8,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            // Line connecting to next status (except for last one or if this is the selected status)
                            if (index < serviceFlow.length - 1 && !isSelected)
                              Container(
                                width: 2,
                                height: 30,
                                color: isPast
                                    ? Colors.grey[400]
                                    : Colors.grey[300],
                              ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        // Status content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Use a row to show status name with optional selection indicator
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      status,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: isCurrent
                                            ? WmsApp.grabGreen
                                            : statusColor,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: WmsApp.grabGreen.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        "Selected",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: WmsApp.grabGreen,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (!isSelected) ...[
                                const SizedBox(height: 4),
                                // Display start and end times if available
                                if (hasUpdate &&
                                    statusUpdate.startAt != null) ...[
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.play_circle_outlined,
                                        size: 14,
                                        color: Colors.blue[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        "Started: ${DateFormat("MMM dd, h:mm a").format(statusUpdate.startAt!)}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.blue[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  if (statusUpdate.endAt != null)
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          size: 14,
                                          color: Colors.green[700],
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Completed: ${DateFormat("MMM dd, h:mm a").format(statusUpdate.endAt!)}",
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  const SizedBox(height: 4),
                                ],
                                if (hasUpdate && statusUpdate.notes.isNotEmpty)
                                  Text(
                                    statusUpdate.notes.length > 50
                                        ? '${statusUpdate.notes.substring(0, 50)}...'
                                        : statusUpdate.notes,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                if (isCurrent) ...[
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing:
                                        8, // horizontal spacing between items
                                    runSpacing:
                                        8, // vertical spacing between lines
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: WmsApp.grabGreen.withOpacity(
                                            0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.schedule,
                                              size: 14,
                                              color: WmsApp.grabGreen,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Current Stage",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: WmsApp.grabGreen,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          border: Border.all(
                                            color: Colors.amber.withOpacity(
                                              0.5,
                                            ),
                                            width: 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.timer_outlined,
                                              size: 14,
                                              color: Colors.amber[800],
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              "Est. ${TrackingBackend.getEstimatedTime(status)}",
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Colors.amber[800],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // No longer showing inline details - now using dialog
              ],
            );
          }),
        ],
      ),
    );
  }

  // The inline stage details section has been removed as it's been replaced by the dialog popup

  // Horizontal progress indicator with icons
  Widget _buildHorizontalStepper() {
    // Use the service flow order rather than allStatuses for display
    final serviceFlow = [
      TrackingBackend.vehicleReceived,
      TrackingBackend.initialDiagnosis,
      TrackingBackend.inInspection,
      TrackingBackend.partsAwaiting,
      TrackingBackend.inRepair,
      TrackingBackend.qualityCheck,
      TrackingBackend.finalTesting,
      TrackingBackend.readyForCollection,
    ];

    // Calculate progress value based on service flow, not allStatuses
    final currentStatus = widget.tracking.currentStatus;
    final currentFlowIndex = serviceFlow.indexOf(currentStatus);

    // Do not auto-complete Ready for Collection; keep as current/active
    final isComplete = false;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Service Progress",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: WmsApp.grabDark,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40, // Made even more compact
            child: Row(
              children: [
                const SizedBox(width: 16),
                ...List.generate(serviceFlow.length, (index) {
                  final isPast = index < currentFlowIndex && !isComplete;
                  final isCurrent = index == currentFlowIndex && !isComplete;
                  final status = serviceFlow[index];

                  // Determine colors based on status
                  final iconColor = isPast || isCurrent
                      ? WmsApp.grabGreen
                      : Colors.grey[400];
                  final backgroundColor = (isPast || isCurrent)
                      ? WmsApp.grabGreen.withOpacity(0.1)
                      : Colors.grey[200];

                  return Expanded(
                    child: Row(
                      children: [
                        // Status icon
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: backgroundColor,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  TrackingBackend.getStatusIcon(status),
                                  color: iconColor,
                                  size: 16,
                                ),
                              ),
                            ),
                            if (isPast)
                              Positioned(
                                right: 0,
                                bottom: 0,
                                child: Container(
                                  width: 16,
                                  height: 16,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: WmsApp.grabGreen,
                                      width: 1,
                                    ),
                                  ),
                                  child: Center(
                                    child: Icon(
                                      Icons.check,
                                      color: WmsApp.grabGreen,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),

                        // Connecting line (except for last item)
                        if (index < serviceFlow.length - 1)
                          Expanded(
                            child: Container(
                              height: 2,
                              color: isPast
                                  ? WmsApp.grabGreen
                                  : Colors.grey[300],
                            ),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // This method has been replaced by _buildSimplifiedVerticalTimeline

  // This method has been replaced by _buildSimplifiedVerticalTimeline

  // The chat section has been removed as per requirements

  // Method to show stage details by navigating to a dedicated page
  void _showStageDetailsPage(String status, StatusUpdate? statusUpdate) {
    // Create a non-nullable copy of the status update
    final StatusUpdate update =
        statusUpdate ??
        StatusUpdate(
          status: status,
          timestamp: DateTime.now(),
          notes: "No updates available for this status yet.",
          imageUrls: [],
        );

    // Navigate to the new dedicated stage details page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StageDetailsPage(
          status: status,
          update: update,
          tracking: widget.tracking,
        ),
      ),
    );
  }

  // Method removed as it's not used - we now use StageDetailsPage instead
}
