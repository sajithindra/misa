import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'notification_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class StreamingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const StreamingPage({super.key, required this.cameras});

  @override
  State<StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<StreamingPage> {
  static const platform = MethodChannel('com.example.misa/camera');
  CameraController? _controller;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isProcessingFrame = false;

  // Default connection IP address for the streaming server
  final TextEditingController _ipController = TextEditingController(
    text: '172.20.25.16',
  );

  @override
  void initState() {
    super.initState();
    if (widget.cameras.isNotEmpty) {
      // Use the front camera if available, else first camera
      final camera = widget.cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => widget.cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      _controller!
          .initialize()
          .then((_) {
            if (!mounted) return;
            setState(() {});
          })
          .catchError((e) {
            debugPrint("Camera initialization error: $e");
          });
    }
  }

  void _toggleConnection() {
    if (_isConnected) {
      _disconnect();
    } else {
      _connect();
    }
  }

  void _connect() {
    try {
      final ip = _ipController.text.trim();
      final uriStr = 'ws://$ip:8000/ws/stream';
      final uri = Uri.parse(uriStr);
      _channel = WebSocketChannel.connect(uri);

      setState(() {
        _isConnected = true;
      });

      // Also connect to alerts via NotificationService
      context.read<NotificationService>().connect(ip);

      _channel!.stream.listen(
        (message) {
          debugPrint('Server stream message: $message');
        },
        onDone: () {
          _disconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _disconnect();
        },
      );

      _startStreaming();
    } catch (e) {
      debugPrint('Connection failed: $e');
    }
  }

  void _disconnect() {
    if (_controller?.value.isStreamingImages == true) {
      _controller?.stopImageStream();
    }
    _channel?.sink.close();
    context.read<NotificationService>().disconnect();
    if (mounted) {
      setState(() {
        _isConnected = false;
      });
    }
  }

  void _startStreaming() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Track FPS locally to allow for potential throttling, though we'll aim for as many as possible natively
    int timeSinceLastFrame = DateTime.now().millisecondsSinceEpoch;

    try {
      _controller!.startImageStream((CameraImage image) async {
        if (_isProcessingFrame || !_isConnected) return;

        // Throttling to max 30 FPS (~33ms per frame) to not overwhelm system/network
        int now = DateTime.now().millisecondsSinceEpoch;
        if (now - timeSinceLastFrame < 33) return;

        timeSinceLastFrame = now;
        _isProcessingFrame = true;

        try {
          Uint8List? processedBytes;

          if (defaultTargetPlatform == TargetPlatform.android) {
            final planes = image.planes.map((plane) {
              return {
                'bytes': plane.bytes,
                'bytesPerRow': plane.bytesPerRow,
                'bytesPerPixel': plane.bytesPerPixel,
              };
            }).toList();

            final result = await platform.invokeMethod('compressFrame', {
              'platform': 'android',
              'planes': planes,
              'width': image.width,
              'height': image.height,
              'targetWidth': 480,
            });
            processedBytes = result as Uint8List?;
          } else if (defaultTargetPlatform == TargetPlatform.iOS) {
            final plane = image.planes[0];
            final result = await platform.invokeMethod('compressFrame', {
              'platform': 'ios',
              'bytes': plane.bytes,
              'bytesPerRow': plane.bytesPerRow,
              'width': image.width,
              'height': image.height,
              'targetWidth': 480,
            });
            processedBytes = result as Uint8List?;
          }

          if (processedBytes != null && _isConnected) {
            _channel?.sink.add(processedBytes);
            // debugPrint('Sent frame: ${processedBytes.length} bytes');
          }
        } catch (e) {
          debugPrint('Error streaming frame: $e');
        } finally {
          _isProcessingFrame = false;
        }
      });
    } catch (e) {
      debugPrint("Could not start image stream: $e");
    }
  }

  @override
  void dispose() {
    if (_controller?.value.isStreamingImages == true) {
      _controller?.stopImageStream();
    }
    _channel?.sink.close();
    _controller?.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full Screen Camera Background
          if (_controller != null && _controller!.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.previewSize?.height ?? 1,
                height: _controller!.value.previewSize?.width ?? 1,
                child: CameraPreview(_controller!),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // 2. Safe Area UI Overlay
          SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Top Header (Optional subtle back button)
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),

                // Bottom Control Panel
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.black87, Colors.transparent],
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      stops: [0.3, 1.0],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // IP Address Input
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: TextField(
                          controller: _ipController,
                          enabled: !_isConnected,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 16,
                            ),
                            hintText: 'Enter Server IP',
                            hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Connect / Stream Toggle Button
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _toggleConnection,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isConnected
                                ? Colors.redAccent
                                : Colors.white,
                            foregroundColor: _isConnected
                                ? Colors.white
                                : Colors.black87,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _isConnected ? 'STOP STREAMING' : 'START STREAM',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Live Indicator overlaid on video when connected
          if (_isConnected)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, color: Colors.white, size: 12),
                    SizedBox(width: 8),
                    Text(
                      'LIVE 30FPS',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 4. Alerts Overlay
          _buildAlertsOverlay(),
        ],
      ),
    );
  }

  Widget _buildAlertsOverlay() {
    return Consumer<NotificationService>(
      builder: (context, notificationService, child) {
        if (notificationService.alerts.isEmpty) return const SizedBox.shrink();

        return Positioned(
          top: MediaQuery.of(context).padding.top + 60,
          left: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: notificationService.alerts.take(3).map((alert) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  alert.type,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  DateFormat(
                                    'HH:mm:ss',
                                  ).format(alert.timestamp),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              alert.message,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
