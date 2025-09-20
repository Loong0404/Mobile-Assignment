import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:flutter/services.dart';
import '../main.dart';
import '../backend/tracking.dart';
import '../backend/tracking_service.dart';
import '../backend/profile.dart' as prof;

class ChatRoomPage extends StatefulWidget {
  final String technicianId;
  final String bookingId;
  final String trackId;

  const ChatRoomPage({
    super.key,
    required this.technicianId,
    required this.bookingId,
    required this.trackId,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final List<_UiMessage> _messages = [];
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  StreamSubscription? _sub;

  // Preset quick replies related to car status and service progress
  static const List<String> _quickReplies = [
    "What's the status of my car?",
    "Has servicing started?",
    "Any issues found so far?",
    "When will it be ready?",
    "Estimated cost update, please",
    "Any parts pending?",
    "Can I pick up today?",
    "Please share progress photos",
  ];

  @override
  void initState() {
    super.initState();
    // Ensure technician profiles are present so header can resolve the name
    Future(() async {
      await TrackingService.instance.seedTechniciansIfEmpty();
      _listenMessages();
    });
  }

  void _listenMessages() {
    _sub = ChatService.instance.streamMessages(widget.trackId).listen((items) {
      setState(() {
        _messages
          ..clear()
          ..addAll(items.map(_UiMessage.fromData));
      });
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _sub?.cancel();
    super.dispose();
  }

  // Show attachment options bottom sheet
  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  "Attach Media",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: WmsApp.grabGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.camera_alt, color: WmsApp.grabGreen),
                ),
                title: const Text("Take Photo"),
                subtitle: const Text("Capture a new photo with camera"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: WmsApp.grabGreen.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.photo_library, color: WmsApp.grabGreen),
                ),
                title: const Text("Choose from Gallery"),
                subtitle: const Text("Select photo from your device"),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  // Pick image from camera or gallery
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedImage = await _imagePicker.pickImage(
        source: source,
        imageQuality: 70, // Reduce quality to save bandwidth
      );

      if (pickedImage != null) {
        // Send the image message
        _sendImageMessage(pickedImage.path);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error picking image: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Send an image message
  void _sendImageMessage(String imagePath) async {
    // Create a placeholder message with uploading status
    final message = _UiMessage(
      text: "Image",
      isFromTechnician: false,
      timestamp: DateTime.now(),
      imageUrl: imagePath,
    );

    setState(() {
      _messages.add(message);
    });

    // Auto-scroll to the bottom
    _scrollToBottom();

    // Upload and send to Firestore
    final url = await ChatService.instance.uploadImage(
      widget.trackId,
      imagePath,
    );
    await ChatService.instance.sendImage(
      trackId: widget.trackId,
      imageUrl: url,
      displayName: (prof.ProfileBackend.instance.currentUser?.name ?? 'You'),
      userId: (prof.ProfileBackend.instance.currentUser?.userId ?? ''),
    );
  }

  // Scroll to bottom of chat
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Send current location as a map preview + link text
  Future<void> _sendCurrentLocation() async {
    try {
      // Ensure device location services are enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
        await Geolocator.openLocationSettings();
        return;
      }
      // Check and request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied')),
          );
        }
        return;
      }

      // Get current position
      final pos = await Geolocator.getCurrentPosition();
      final lat = pos.latitude.toStringAsFixed(6);
      final lng = pos.longitude.toStringAsFixed(6);
      final mapsUrl = 'https://www.google.com/maps?q=$lat,$lng';

      // Send the map link as a simple text message; preview will render in UI
      await ChatService.instance.sendMessage(
        trackId: widget.trackId,
        text: 'My current location: $mapsUrl',
        displayName: (prof.ProfileBackend.instance.currentUser?.name ?? 'You'),
        userId: (prof.ProfileBackend.instance.currentUser?.userId ?? ''),
      );
    } on PlatformException catch (e) {
      if (e.code.toLowerCase().contains('missing')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Plugin not registered. Fully restart the app.'),
            ),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to share location: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to share location: $e')));
      }
    }
  }

  // Simulate technician response
  // technician replies are expected from backend updates

  void _handleSend() {
    if (_textController.text.trim().isEmpty) return;
    final text = _textController.text.trim();
    _textController.clear();
    ChatService.instance.sendMessage(
      trackId: widget.trackId,
      text: text,
      displayName: (prof.ProfileBackend.instance.currentUser?.name ?? 'You'),
      userId: (prof.ProfileBackend.instance.currentUser?.userId ?? ''),
    );
    _scrollToBottom();
  }

  // Send a preset quick reply
  void _sendQuickReply(String text) {
    ChatService.instance.sendMessage(
      trackId: widget.trackId,
      text: text,
      displayName: (prof.ProfileBackend.instance.currentUser?.name ?? 'You'),
      userId: (prof.ProfileBackend.instance.currentUser?.userId ?? ''),
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Technician?>(
      stream: TrackingService.instance.streamTechnician(widget.technicianId),
      builder: (context, snapshot) {
        final tech = snapshot.data;
        final hasAvatar = (tech?.avatarUrl ?? '').isNotEmpty;
        final displayName = tech?.name ?? 'Technician ${widget.technicianId}';
        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                CircleAvatar(
                  backgroundImage: hasAvatar
                      ? NetworkImage(tech!.avatarUrl)
                      : null,
                  radius: 16,
                  backgroundColor: Colors.grey[300],
                  child: !hasAvatar
                      ? Text(
                          displayName[0].toUpperCase(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(displayName, style: const TextStyle(fontSize: 16)),
                    Text(
                      "Booking ${widget.bookingId}",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            backgroundColor: WmsApp.grabGreen,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Chat Information"),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "You are chatting with $displayName",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text("Response hours: Monday-Friday, 9AM-5PM"),
                          const SizedBox(height: 8),
                          const Text(
                            "For urgent matters, please call our service center directly.",
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          child: const Text("Close"),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
          body: Column(
            children: [
              // Chat messages list
              Expanded(
                child: Container(
                  color: Colors.grey[100],
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final showTimestamp =
                          index == 0 ||
                          _messages[index].timestamp.day !=
                              _messages[index - 1].timestamp.day;

                      return Column(
                        children: [
                          if (showTimestamp)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _formatDateForTimestamp(message.timestamp),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          _buildMessageBubble(message, tech),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Quick reply bar
              _buildQuickReplyBar(),

              // Message input area
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, -1),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      // Attachment button
                      IconButton(
                        icon: Icon(Icons.attach_file, color: Colors.grey[600]),
                        onPressed: _showAttachmentOptions,
                      ),

                      // Send location button
                      IconButton(
                        icon: Icon(Icons.my_location, color: Colors.grey[600]),
                        tooltip: 'Send current location',
                        onPressed: _sendCurrentLocation,
                      ),

                      // Camera quick access removed (use Attach Media)

                      // Text input field
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Colors.grey[200],
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                          onSubmitted: (_) => _handleSend(),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Send button
                      Material(
                        color: WmsApp.grabGreen,
                        borderRadius: BorderRadius.circular(24),
                        child: InkWell(
                          onTap: _handleSend,
                          borderRadius: BorderRadius.circular(24),
                          child: Container(
                            width: 44,
                            height: 44,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Quick reply bar with horizontally scrollable chips
  Widget _buildQuickReplyBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _quickReplies
              .map(
                (q) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildQuickReplyChip(q),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildQuickReplyChip(String text) {
    return ActionChip(
      backgroundColor: WmsApp.grabGreen.withValues(alpha: 0.08),
      shape: StadiumBorder(
        side: BorderSide(color: WmsApp.grabGreen.withValues(alpha: 0.3)),
      ),
      label: Text(text, style: TextStyle(color: WmsApp.grabDark, fontSize: 12)),
      onPressed: () => _sendQuickReply(text),
    );
  }

  Widget _buildMessageBubble(_UiMessage message, Technician? tech) {
    final isFromTechnician = message.isFromTechnician;
    final backgroundColor = isFromTechnician
        ? Colors.grey[200]
        : WmsApp.grabGreen.withValues(alpha: 0.1);

    final textColor = isFromTechnician ? Colors.black87 : WmsApp.grabDark;

    final alignment = isFromTechnician
        ? CrossAxisAlignment.start
        : CrossAxisAlignment.end;

    final maybeMap = _buildMapPreviewIfLocation(message.text);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: isFromTechnician
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (isFromTechnician)
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: CircleAvatar(
                backgroundImage: (tech?.avatarUrl ?? '').isNotEmpty
                    ? NetworkImage(tech!.avatarUrl)
                    : null,
                radius: 16,
                backgroundColor: Colors.grey[300],
                child: ((tech?.avatarUrl ?? '').isEmpty)
                    ? Text(
                        (tech?.name ?? 'Technician ${widget.technicianId}')[0]
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
            ),
          // no system message icon
          Column(
            crossAxisAlignment: alignment,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(16).copyWith(
                    bottomLeft: isFromTechnician
                        ? Radius.zero
                        : const Radius.circular(16),
                    bottomRight: isFromTechnician
                        ? const Radius.circular(16)
                        : Radius.zero,
                  ),
                  border: null,
                ),
                child: message.imageUrl != null
                    ? _buildImageMessage(message)
                    : maybeMap ??
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            child: Text(
                              message.text,
                              style: TextStyle(fontSize: 14, color: textColor),
                            ),
                          ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTimeForMessage(message.timestamp),
                style: TextStyle(fontSize: 10, color: Colors.grey[600]),
              ),
            ],
          ),
          if (!isFromTechnician)
            const Padding(
              padding: EdgeInsets.only(left: 8, top: 8),
              child: Icon(Icons.check_circle, size: 16, color: Colors.green),
            ),
        ],
      ),
    );
  }

  // Detect and render a small map preview when a message contains a maps link with lat,lng
  Widget? _buildMapPreviewIfLocation(String text) {
    final reg = RegExp(
      r'https?:\/\/www\.google\.com\/maps\?q=([\-\d\.]+),([\-\d\.]+)',
    );
    final m = reg.firstMatch(text);
    if (m == null) return null;
    final lat = double.tryParse(m.group(1) ?? '');
    final lng = double.tryParse(m.group(2) ?? '');
    if (lat == null || lng == null) return null;
    final center = ll.LatLng(lat, lng);
    final link = Uri.parse(
      'https://www.google.com/maps?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 160,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                  userAgentPackageName: 'com.example.mobile_assigment',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: center,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        TextButton.icon(
          onPressed: () async {
            // Prefer geo: scheme to open native map apps; fallback to https
            final geo = Uri.parse(
              'geo:${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
            );
            bool launched = false;
            try {
              if (await canLaunchUrl(geo)) {
                launched = await launchUrl(
                  geo,
                  mode: LaunchMode.externalApplication,
                );
              }
              if (!launched) {
                launched = await launchUrl(
                  link,
                  mode: LaunchMode.externalApplication,
                );
              }
            } catch (_) {
              launched = false;
            }
            if (!launched && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No maps app found to open the location'),
                ),
              );
            }
          },
          icon: const Icon(Icons.map),
          label: const Text('Open in Google Maps'),
        ),
      ],
    );
  }

  // Build image message content
  Widget _buildImageMessage(_UiMessage message) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Image
          message.imageUrl!.startsWith('http')
              ? Image.network(
                  message.imageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                )
              : Image.file(
                  File(message.imageUrl!),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                ),

          // no uploading overlay (messages come from Firestore)
        ],
      ),
    );
  }

  String _formatDateForTimestamp(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return "Today";
    } else if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day - 1) {
      return "Yesterday";
    } else {
      return "${date.day}/${date.month}/${date.year}";
    }
  }

  String _formatTimeForMessage(DateTime date) {
    return "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
  }
}

// UI adapter message
class _UiMessage {
  final String text;
  final bool isFromTechnician;
  final DateTime timestamp;
  final String? imageUrl;

  _UiMessage({
    required this.text,
    required this.isFromTechnician,
    required this.timestamp,
    this.imageUrl,
  });

  factory _UiMessage.fromData(ChatMessage m) {
    return _UiMessage(
      text: m.message,
      isFromTechnician: m.isFromTechnician,
      timestamp: m.timestamp,
      imageUrl: m.images.isNotEmpty ? m.images.first : null,
    );
  }
}
