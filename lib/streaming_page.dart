import 'dart:async';
import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class StreamingPage extends StatefulWidget {
  final List<CameraDescription> cameras;
  const StreamingPage({super.key, required this.cameras});

  @override
  State<StreamingPage> createState() => _StreamingPageState();
}

class _StreamingPageState extends State<StreamingPage> {
  CameraController? _controller;
  WebSocketChannel? _channel;
  Timer? _timer;
  bool _isConnected = false;

  // Defaulting to 10.0.2.2 which is the Android emulator's alias to localhost.
  // iOS simulator uses localhost directly. You can edit this.
  final TextEditingController _urlController = TextEditingController(
    text: 'ws://10.0.2.2:8000/ws/stream/mobile_app_stream_1',
  );

  final List<String> _alerts = [];

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
      final uri = Uri.parse(_urlController.text);
      _channel = WebSocketChannel.connect(uri);

      setState(() {
        _isConnected = true;
        _alerts.insert(0, 'Connected to server: ${uri.toString()}');
      });

      _channel!.stream.listen(
        (message) {
          debugPrint('Server alert: $message');
          if (mounted) {
            setState(() {
              _alerts.insert(0, 'Alert: $message');
              if (_alerts.length > 50) _alerts.removeLast();
            });
          }
        },
        onDone: () {
          _disconnect();
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          if (mounted) {
            setState(() {
              _alerts.insert(0, 'Error: $error');
            });
          }
          _disconnect();
        },
      );

      _startStreaming();
    } catch (e) {
      debugPrint('Connection failed: $e');
      setState(() {
        _alerts.insert(0, 'Connection failed: $e');
      });
    }
  }

  void _disconnect() {
    _timer?.cancel();
    _channel?.sink.close();
    if (mounted) {
      setState(() {
        _isConnected = false;
        _alerts.insert(0, 'Disconnected');
      });
    }
  }

  void _startStreaming() {
    // Take and send a picture every 500 milliseconds (2 FPS)
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          !_controller!.value.isTakingPicture) {
        try {
          final XFile file = await _controller!.takePicture();
          final bytes = await file.readAsBytes();

          // Send as base64
          final base64String = base64Encode(bytes);
          _channel?.sink.add(base64String);

          debugPrint('Sent frame: ${base64String.length} chars');
        } catch (e) {
          debugPrint('Error capturing/sending frame: $e');
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel?.sink.close();
    _controller?.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Camera Stream')),
      body: Column(
        children: [
          // Camera Preview Area
          if (_controller != null && _controller!.value.isInitialized)
            Expanded(
              flex: 3,
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: CameraPreview(_controller!),
              ),
            )
          else
            const Expanded(
              flex: 3,
              child: Center(child: Text('Initializing Camera...')),
            ),

          // Controls Area
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    labelText: 'WebSocket URL',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.black54,
                  ),
                  enabled: !_isConnected,
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _toggleConnection,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isConnected ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      _isConnected ? 'STOP STREAMING' : 'CONNECT & STREAM',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Output Alerts Area
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Server Alerts:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            flex: 2,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _alerts.length,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    _alerts[index],
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
