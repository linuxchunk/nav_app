import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_gemini/flutter_gemini.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:io';
import 'dart:async';
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
  late FlutterTts _flutterTts;
  late Timer _captureTimer;
  String? analysisResult;
  File? capturedImage;
  final TextEditingController _chatController = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _isAnalyzing = false;
  bool _isSpeaking = false;
  bool _isAutoCapturing = true; // Start with auto-capture enabled
  String _errorMessage = '';
  int _analyzeCount = 0;
  bool _isFirstCapture = true;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _initializeCamera();
    _initTts();

    // Initial message for visually impaired users
    Future.delayed(Duration(seconds: 5), () {
      _speak(
          "Navigation assistant ready. Taking pictures every 8 seconds to help you navigate. Tap the screen once to ask a question, double tap to toggle auto-capture.");
    });

    // Start the auto-capture timer after camera initialization
    _initializeControllerFuture.then((_) {
      _startAutoCaptureTimer();
    });
  }

  void _startAutoCaptureTimer() {
    _captureTimer = Timer.periodic(Duration(seconds: 8), (timer) {
      if (_isAutoCapturing && !_isAnalyzing) {
        _captureAndAnalyze();
      }
    });
  }

  // Initialize the TTS engine
  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.7); // Slightly faster for navigation
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  // Speak the text
  Future<void> _speak(String text) async {
    if (text.isNotEmpty) {
      setState(() {
        _isSpeaking = true;
      });
      await _flutterTts.stop(); // Stop any ongoing speech first
      await _flutterTts.speak(text);
    }
  }

  // Stop speaking
  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isDenied) {
      if (mounted) {
        _speak("Camera permission is required for navigation assistance.");
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Camera Permission Required'),
            content:
                const Text('This app needs camera access to help you navigate'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      setState(() {
        _errorMessage = 'Camera permission denied';
      });
    }
  }

  void _initializeCamera() {
    _controller = CameraController(
      widget.camera,
      ResolutionPreset.low, // Use low resolution for faster processing
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );
    _initializeControllerFuture = _controller.initialize().then((_) {
      if (mounted) {
        setState(() {
          _errorMessage = '';
        });
      }
    }).catchError((e) {
      print('Camera initialization error: $e');
      setState(() {
        _errorMessage = 'Failed to initialize camera: $e';
      });
      _speak("Camera failed to initialize. Please restart the app.");
    });
  }

  Future<void> _captureAndAnalyze() async {
    try {
      await _initializeControllerFuture;
      final image = await _controller.takePicture();
      await analyzeImage(image.path);
    } catch (e) {
      print('Error taking picture: $e');
      setState(() {
        _errorMessage = 'Error taking picture: $e';
      });
      _speak("Failed to capture image.");
    }
  }

  Future<void> analyzeImage(String imagePath) async {
    // Stop any ongoing speech
    await _stopSpeaking();

    setState(() {
      _isAnalyzing = true;
      capturedImage = File(imagePath);
      _errorMessage = '';
    });

    _analyzeCount++;

    final gemini = Gemini.instance;
    try {
      // For visually impaired navigation, use a more specific prompt
      final String prompt = _isFirstCapture
          ? "You're helping a visually impaired person navigate. In 1-2 short sentences, describe the key elements you see that would help with navigation. Focus on obstacles, paths, doors, stairs, and orientation. Be very concise."
          : "In 1-2 short sentences, describe only what has changed from previous scene that would help with navigation. Focus on obstacles, paths, doors, stairs, and orientation. Be very concise.";

      final response = await gemini.prompt(parts: [
        Part.text(prompt),
        Part.bytes(await File(imagePath).readAsBytes()),
      ]);

      String analysisText = response?.output ?? 'No analysis available';

      // Truncate long responses for easier listening
      if (analysisText.length > 150) {
        analysisText = analysisText.substring(0, 150) + "...";
      }

      setState(() {
        analysisResult = analysisText;
        _messages.add(ChatMessage(
          text: analysisText,
          isUser: false,
          timestamp: DateTime.now(),
        ));
        _isFirstCapture = false;
      });

      // Speak the analysis result
      await _speak(analysisText);
    } catch (e) {
      print('Error analyzing image: $e');
      _speak("Failed to analyze surroundings.");
    } finally {
      setState(() {
        _isAnalyzing = false;
      });
    }
  }

  Future<void> sendMessage(String message) async {
    if (message.trim().isEmpty || capturedImage == null) {
      _speak("Please take a picture first or provide a question.");
      return;
    }

    // Stop any ongoing speech
    await _stopSpeaking();

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
        Part.text(
            "Answer the following question about the image very briefly in 1-2 sentences: " +
                message),
        Part.bytes(await capturedImage!.readAsBytes()),
      ]);

      String responseText = response?.output ?? 'No response available';

      // Truncate long responses for easier listening
      if (responseText.length > 150) {
        responseText = responseText.substring(0, 150) + "...";
      }

      setState(() {
        _messages.add(ChatMessage(
          text: responseText,
          isUser: false,
          timestamp: DateTime.now(),
        ));
      });

      // Speak the response
      await _speak(responseText);
    } catch (e) {
      print('Error sending message: $e');
      _speak("Failed to answer your question.");
    }
  }

  void _toggleAutoCapture() {
    setState(() {
      _isAutoCapturing = !_isAutoCapturing;
    });

    if (_isAutoCapturing) {
      _speak("Auto-capture enabled. Taking pictures every 5 seconds.");
    } else {
      _speak(
          "Auto-capture disabled. Tap the camera button to take pictures manually.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundBlack,
      body: SafeArea(
        child: Stack(
          children: [
            // Full screen gesture detector for easy tap access by visually impaired users
            GestureDetector(
              onTap: () {
                // Single tap shows the voice input dialog
                _showVoiceInputDialog();
              },
              onDoubleTap: () {
                // Double tap toggles auto-capture
                _toggleAutoCapture();
              },
              child: Column(
                children: [
                  _buildCameraPreview(),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: kSurfaceBlack,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(20)),
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
                          _buildAccessibilityStatusBar(),
                          Expanded(
                            child: _buildChatList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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

  Widget _buildAccessibilityStatusBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kGrey,
        border: Border(bottom: BorderSide(color: kPrimaryGreen, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Auto-capture status
          Row(
            children: [
              Icon(
                _isAutoCapturing ? Icons.timer : Icons.timer_off,
                color: _isAutoCapturing ? kPrimaryGreen : Colors.white70,
                size: 20,
              ),
              SizedBox(width: 4),
              Text(
                _isAutoCapturing ? "Auto On" : "Auto Off",
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
          // TTS status
          GestureDetector(
            onTap: () {
              if (_isSpeaking) {
                _stopSpeaking();
              } else {
                if (_messages.isNotEmpty) {
                  final lastAiMessage = _messages.lastWhere(
                      (msg) => !msg.isUser,
                      orElse: () => _messages.last);
                  _speak(lastAiMessage.text);
                }
              }
            },
            child: Row(
              children: [
                Icon(
                  _isSpeaking ? Icons.volume_up : Icons.volume_mute,
                  color: _isSpeaking ? kPrimaryGreen : Colors.white70,
                  size: 20,
                ),
                SizedBox(width: 4),
                Text(
                  _isSpeaking ? "Speaking" : "Silent",
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
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
                if (snapshot.connectionState == ConnectionState.done &&
                    _errorMessage.isEmpty) {
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
                } else if (_errorMessage.isNotEmpty) {
                  return Center(
                    child: Text(
                      _errorMessage,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  );
                } else {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: kPrimaryGreen,
                    ),
                  );
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
            // Show a large, accessible label at the bottom of the camera preview
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 8),
                color: Colors.black.withOpacity(0.6),
                child: Text(
                  _isAutoCapturing
                      ? "Auto-scanning every 5 seconds"
                      : "Single tap: Ask a question   Double tap: Toggle auto-scan",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
        onPressed: _captureAndAnalyze,
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
            fontSize: 16, // Larger text for better accessibility
          ),
        ),
      ),
    );
  }

  void _showVoiceInputDialog() {
    // For now, showing a simple text input dialog
    // In a real app, you would implement voice input here
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kSurfaceBlack,
        title: Text(
          "Ask about your surroundings",
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: _chatController,
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: "Example: Are there any stairs?",
            hintStyle: TextStyle(color: Colors.grey),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: kPrimaryGreen),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              final message = _chatController.text;
              Navigator.pop(context);
              if (message.isNotEmpty) {
                sendMessage(message);
              }
            },
            child: Text("Ask", style: TextStyle(color: kPrimaryGreen)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _chatController.dispose();
    _flutterTts.stop();
    _captureTimer.cancel();
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
