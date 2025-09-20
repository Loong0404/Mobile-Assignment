import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../main.dart';
import '../backend/tracking.dart';
import '../backend/tracking_service.dart';
import 'chat_room.dart';

class StageDetailsPage extends StatelessWidget {
  final String status;
  final StatusUpdate update;
  final ServiceTracking tracking;

  const StageDetailsPage({
    super.key,
    required this.status,
    required this.update,
    required this.tracking,
  });

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) {
      return '${duration.inDays} day${duration.inDays > 1 ? "s" : ""} ${duration.inHours % 24} hr${duration.inHours % 24 != 1 ? "s" : ""}';
    } else if (duration.inHours > 0) {
      return '${duration.inHours} hr${duration.inHours != 1 ? "s" : ""} ${duration.inMinutes % 60} min';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes} min';
    } else {
      return '${duration.inSeconds} seconds';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("$status Details"),
        backgroundColor: WmsApp.grabGreen,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with status icon
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: TrackingBackend.getStatusColor(
                        status,
                      ).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      TrackingBackend.getStatusIcon(status),
                      color: TrackingBackend.getStatusColor(status),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: TrackingBackend.getStatusColor(status),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Updated timestamp with status update time
                            Row(
                              children: [
                                Icon(
                                  Icons.access_time,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  DateFormat(
                                    "MMM dd, yyyy 'at' h:mm a",
                                  ).format(update.timestamp),
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),

                            // Show start and end times if available
                            if (update.startAt != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.play_circle_outline,
                                    size: 16,
                                    color: Colors.blue[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Started: ${DateFormat("MMM dd, yyyy 'at' h:mm a").format(update.startAt!)}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.blue[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            if (update.endAt != null) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 16,
                                    color: Colors.green[700],
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    "Completed: ${DateFormat("MMM dd, yyyy 'at' h:mm a").format(update.endAt!)}",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Image if available
              if (update.imageUrls.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    height: 260,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          update.imageUrls[0],
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value:
                                    loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                    : null,
                                color: WmsApp.grabGreen,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.grey[200],
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      size: 64,
                                      color: Colors.grey[400],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      "Image could not be loaded",
                                      style: TextStyle(color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Stage duration indicator (if both start and end times are available)
              if (update.startAt != null && update.endAt != null) ...[
                Card(
                  elevation: 1,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Stage Duration",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: WmsApp.grabDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.timer,
                                color: Colors.blue[700],
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _formatDuration(
                                      update.endAt!.difference(update.startAt!),
                                    ),
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                  Text(
                                    "Time taken to complete this stage",
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Notes section
              Card(
                elevation: 1,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Technician Notes:",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: WmsApp.grabDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Builder(
                        builder: (context) {
                          final lines = <String>[];
                          final ids = tracking.serviceIds ?? const <String>[];
                          final types =
                              tracking.serviceTypes ?? const <String>[];
                          if (ids.isNotEmpty) {
                            for (var i = 0; i < ids.length; i++) {
                              final id = ids[i];
                              final type = (i < types.length)
                                  ? types[i].toString()
                                  : '';
                              final label = [
                                id,
                                if (type.isNotEmpty) type,
                              ].join(' • ');
                              lines.add('- $label');
                            }
                          } else {
                            final id = tracking.serviceId ?? '';
                            final type = tracking.serviceType ?? '';
                            final label = [
                              if (id.isNotEmpty) id,
                              if (type.isNotEmpty) type,
                            ].join(' • ');
                            if (label.isNotEmpty) lines.add('- $label');
                          }

                          final enrichedNotes = [
                            update.notes.trim(),
                            if (lines.isNotEmpty) '',
                            if (lines.isNotEmpty) 'Selected services:',
                            ...lines,
                          ].join('\n');

                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey[200]!),
                            ),
                            child: Text(
                              enrichedNotes,
                              style: const TextStyle(fontSize: 16, height: 1.5),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Technician info
              Card(
                elevation: 1,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Service Technician:",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: WmsApp.grabDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<Technician?>(
                        stream: TrackingService.instance.streamTechnician(
                          tracking.technicianId,
                        ),
                        builder: (context, snapshot) {
                          final Technician? tech =
                              snapshot.data ?? tracking.technician;
                          final hasAvatar = (tech?.avatarUrl ?? '').isNotEmpty;
                          final skills =
                              tech?.skills ??
                              tracking.technician?.skills ??
                              const <String>[];
                          return GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  final name =
                                      tech?.name ??
                                      'Technician ${tracking.technicianId}';
                                  final hasAvatarDialog =
                                      (tech?.avatarUrl ?? '').isNotEmpty;
                                  return Dialog(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Container(
                                      constraints: BoxConstraints(
                                        maxWidth: 600,
                                        maxHeight:
                                            MediaQuery.of(context).size.height *
                                            0.85,
                                      ),
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                "Technician Profile",
                                                style: TextStyle(
                                                  fontSize: 22,
                                                  fontWeight: FontWeight.bold,
                                                  color: WmsApp.grabDark,
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 20,
                                                ),
                                                onPressed: () =>
                                                    Navigator.of(context).pop(),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                color: Colors.grey[600],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          Container(
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.1),
                                                  spreadRadius: 2,
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: CircleAvatar(
                                              backgroundImage: hasAvatarDialog
                                                  ? NetworkImage(
                                                      tech!.avatarUrl,
                                                    )
                                                  : null,
                                              radius: 60,
                                              backgroundColor: Colors.grey[300],
                                              child: !hasAvatarDialog
                                                  ? Text(
                                                      (name)[0].toUpperCase(),
                                                      style: const TextStyle(
                                                        fontSize: 48,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Colors.white,
                                                      ),
                                                    )
                                                  : null,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontSize: 24,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            "${skills.isNotEmpty ? skills[0] : 'Service'} Technician",
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.work,
                                                color: Colors.grey[700],
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                "${tech?.yearsExperience ?? tracking.technician?.yearsExperience ?? 0} years of experience",
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  color: Colors.grey[700],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 16),
                                          if (skills.isNotEmpty) ...[
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.engineering,
                                                  color: Colors.grey[700],
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        "Skills",
                                                        style: TextStyle(
                                                          fontSize: 16,
                                                          color:
                                                              Colors.grey[700],
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Wrap(
                                                        spacing: 6,
                                                        runSpacing: 6,
                                                        children: skills
                                                            .map(
                                                              (
                                                                skill,
                                                              ) => Container(
                                                                padding:
                                                                    const EdgeInsets.symmetric(
                                                                      horizontal:
                                                                          10,
                                                                      vertical:
                                                                          6,
                                                                    ),
                                                                decoration: BoxDecoration(
                                                                  color: WmsApp
                                                                      .grabGreen
                                                                      .withOpacity(
                                                                        0.1,
                                                                      ),
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        16,
                                                                      ),
                                                                ),
                                                                child: Text(
                                                                  skill,
                                                                  style: TextStyle(
                                                                    fontSize:
                                                                        14,
                                                                    color: WmsApp
                                                                        .grabGreen,
                                                                  ),
                                                                ),
                                                              ),
                                                            )
                                                            .toList(),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                          const SizedBox(height: 24),
                                          ElevatedButton.icon(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (context) =>
                                                      ChatRoomPage(
                                                        technicianId: tracking
                                                            .technicianId,
                                                        bookingId:
                                                            tracking.bookingId,
                                                        trackId: tracking.id,
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.message,
                                              size: 20,
                                            ),
                                            label: const Text(
                                              "Chat with Technician",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: WmsApp.grabGreen,
                                              foregroundColor: Colors.white,
                                              minimumSize: const Size(
                                                double.infinity,
                                                56,
                                              ),
                                              elevation: 2,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 12,
                                                  ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey[200]!),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundImage: hasAvatar
                                        ? NetworkImage(tech!.avatarUrl)
                                        : null,
                                    radius: 24,
                                    backgroundColor: Colors.grey[300],
                                    child: !hasAvatar
                                        ? Text(
                                            (tech?.name ??
                                                    'Technician ${tracking.technicianId}')[0]
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tech?.name ??
                                              'Technician ${tracking.technicianId}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          "${skills.isNotEmpty ? skills[0] : 'Service'} Technician",
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: WmsApp.grabGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Text(
                                      "View Profile",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: WmsApp.grabGreen,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) {
                    return StreamBuilder<Technician?>(
                      stream: TrackingService.instance.streamTechnician(
                        tracking.technicianId,
                      ),
                      builder: (context, snapshot) {
                        return ChatRoomPage(
                          technicianId: tracking.technicianId,
                          bookingId: tracking.bookingId,
                          trackId: tracking.id,
                        );
                      },
                    );
                  },
                ),
              );
            },
            icon: const Icon(Icons.chat, size: 20),
            label: const Text(
              "Chat with Technician",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: WmsApp.grabGreen,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              elevation: 2,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
