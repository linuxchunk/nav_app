import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

const Color kPrimaryGreen = Color(0xFF00C853); // Bright green
const Color kDarkGreen = Color(0xFF2E7D32); // Dark green
const Color kBackgroundBlack = Color(0xFF121212); // Material dark background
const Color kSurfaceBlack = Color(0xFF1E1E1E); // Slightly lighter black
const Color kGrey = Color(0xFF333333); // Dark grey for cards

class CameraScreen extends StatefulWidget {
  final CameraDescription camera;

  const CameraScreen({Key? key, required this.camera}) : super(key: key);

  @override
  CameraScreenState createState() => CameraScreenState();
}

class CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  late Future<void> _initializeControllerFuture;
  String? analysisResult;
  File? capturedImage;
  final TextEditingController _chatController = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      _initializeCamera();
    } else {
      // Show dialog to explain why camera permission is needed
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Camera Permission Required'),
            content:
                const Text('This app needs camera access to analyze images'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _initializeCamera() {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> analyzeImage(String imagePath) async {
    setState(() {
      _isAnalyzing = true;
      capturedImage = File(imagePath);
    });

    final gemini = Gemini.instance;
    try {
      final response = await gemini.prompt(parts: [
        Part.text('Describe what you see in this image in detail:'),
        Part.bytes(await File(imagePath).readAsBytes()),
      ]);

      setState(() {
        analysisResult = response?.output ?? 'No analysis available';
        _messages.add(ChatMessage(
          text: response?.output ?? 'No analysis available',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      setState(() {
        analysisResult = 'Error analyzing image: $e';
      });
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || capturedImage == null) return;

    setState(() {
      _messages.add(ChatMessage(
        text: message,
        isUser: true,
        timestamp: DateTime.now(),
      ));
      _chatController.clear();
    });

    final gemini = Gemini.instance;
    try {
      final response = await gemini.prompt(parts: [
        Part.text(message),
        Part.bytes(await capturedImage!.readAsBytes()),
      ]);

      setState(() {
        _messages.add(ChatMessage(
          text: response?.output ?? 'No response available',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    } catch (e) {
      setState(() {
        _messages.add(ChatMessage(
          text: 'Error: $e',
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundBlack,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildCameraPreview(),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: kSurfaceBlack,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(20)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildTabBar(),
                        Expanded(
                          child: _buildChatList(),
                        ),
                        _buildChatInput(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.4 - 28,
              child: _buildCameraButton(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    final size = MediaQuery.of(context).size;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.4,
      child: ClipRRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FutureBuilder<void>(
              future: _initializeControllerFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.done) {
                  // Get the camera preview size
                  final scale =
                      1 / (_controller.value.aspectRatio * size.aspectRatio);
                  return Transform.scale(
                    scale: scale,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _controller.value.aspectRatio,
                        child: CameraPreview(_controller),
                      ),
                    ),
                  );
                } else {
                  return const Center(
                      child: CircularProgressIndicator(
                    color: kPrimaryGreen,
                  ));
                }
              },
            ),
            if (_isAnalyzing)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(
                    color: kPrimaryGreen,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraButton() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kPrimaryGreen, kDarkGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(50),
        boxShadow: [
          BoxShadow(
            color: kPrimaryGreen.withOpacity(0.3),
            spreadRadius: 2,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () async {
          try {
            await _initializeControllerFuture;
            final image = await _controller.takePicture();
            await analyzeImage(image.path);
          } catch (e) {
            print(e);
          }
        },
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: const Icon(
          Icons.photo_camera_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: kGrey,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];
        return _buildMessageBubble(message);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Align(
      alignment: message.isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.isUser ? kPrimaryGreen : kGrey,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          message.text,
          style: const TextStyle(
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildChatInput() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: kSurfaceBlack,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 5,
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              // Voice input functionality
            },
            icon: const Icon(Icons.mic_rounded),
            color: kPrimaryGreen,
          ),
          Expanded(
            child: TextField(
              controller: _chatController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Ask about the image...',
                hintStyle: TextStyle(color: Colors.grey[400]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: kGrey,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [kPrimaryGreen, kDarkGreen],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: IconButton(
              onPressed: () => sendMessage(_chatController.text),
              icon: const Icon(Icons.send_rounded),
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _chatController.dispose();
    super.dispose();
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
