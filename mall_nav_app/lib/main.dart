import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'dart:collection';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mall Navigation',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const NavigationScreen(),
    );
  }
}

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({Key? key}) : super(key: key);

  @override
  _NavigationScreenState createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  final FlutterTts flutterTts = FlutterTts();
  Timer? _scanTimer;
  String _navigationStatus = "Ready to navigate";
  Map<String, double> _distances = {};
  Map<String, int> _lastRssi = {};
  String _targetLocation = "";
  bool _isScanning = false;
  List<String> _foundBeacons = [];
  double _lastDistance = 0;
  Timer? _navigationTimer;
  int _lastDirection = 0;
  bool _isSpeaking = false;
  Queue<String> _speechQueue = Queue<String>();
  DateTime _lastUpdateTime = DateTime.now();
  bool _hasReachedDestination = false;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  // Object detection related variables
  CameraController? _cameraController;
  ObjectDetector? _objectDetector;
  List<DetectedObject> _detectedObjects = [];
  bool _isCameraInitialized = false;

  final Map<String, String> beaconLocations = {
    "24:DC:C3:45:90:D6": "Mall Entrance",
    "E8:68:EA:F6:BE:90": "Mall Exit"
  };

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _checkBluetoothState();
    _initializeCamera();
  }

  Future<void> _checkBluetoothState() async {
    bool isAvailable = await FlutterBluePlus.isAvailable;
    bool isOn = await FlutterBluePlus.isOn;

    print('Bluetooth available: $isAvailable');
    print('Bluetooth on: $isOn');

    if (!isAvailable) {
      setState(() {
        _navigationStatus = "Bluetooth not available on this device";
      });
      return;
    }

    if (!isOn) {
      setState(() {
        _navigationStatus = "Please turn on Bluetooth";
      });
      return;
    }

    _startScanning();
  }

  Future<void> _initializeTts() async {
    await flutterTts.setLanguage("en-US");
    await flutterTts.setSpeechRate(0.5);
    await flutterTts.setVolume(1.0);
    await flutterTts.setPitch(1.0);

    flutterTts.setCompletionHandler(() {
      _isSpeaking = false;
      _processNextSpeech();
    });
  }

  void _processNextSpeech() {
    if (!_isSpeaking && _speechQueue.isNotEmpty) {
      _isSpeaking = true;
      flutterTts.speak(_speechQueue.removeFirst());
    }
  }

  void _addToSpeechQueue(String message) {
    _speechQueue.add(message);
    _processNextSpeech();
  }

  void _startScanning() async {
    // Cancel any existing scan subscription
    await _scanSubscription?.cancel();

    setState(() {
      _isScanning = true;
      _navigationStatus = "Scanning for beacons...";
    });

    // Start continuous scanning
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        String deviceId = result.device.id.toString();
        print('Found device: $deviceId with RSSI: ${result.rssi}');

        if (beaconLocations.containsKey(deviceId)) {
          print('Found matching beacon: $deviceId');
          double distance = _calculateDistance(
              result.rssi, result.advertisementData.txPowerLevel ?? -59);
          print('Calculated distance: $distance meters');

          setState(() {
            _distances[deviceId] = distance;
            _lastRssi[deviceId] = result.rssi;
            if (!_foundBeacons.contains(deviceId)) {
              _foundBeacons.add(deviceId);
              print('Added new beacon: $deviceId');
            }
          });

          if (_targetLocation == deviceId) {
            _provideNavigation(deviceId, distance, result.rssi);
          }
        }
      }
    });

    // Start periodic scanning
    _scanTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        if (!_isScanning) return;
        await FlutterBluePlus.startScan(
            timeout: const Duration(milliseconds: 500));
      } catch (e) {
        print('Error during scanning: $e');
      }
    });
  }

  double _calculateDistance(int rssi, int txPower) {
    if (rssi == 0) return -1;
    double ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return pow(ratio, 10.0).toDouble();
    } else {
      double accuracy = (0.89976) * pow(ratio, 7.7095) + 0.111;
      return accuracy;
    }
  }

  String _getClockDirection(int rssi) {
    int lastRssi = _lastRssi[_targetLocation] ?? rssi;
    int direction;

    if (rssi > lastRssi + 5) {
      direction = _lastDirection;
    } else if (rssi < lastRssi - 5) {
      direction = (_lastDirection + 3) % 12;
    } else {
      direction = _lastDirection;
    }

    _lastDirection = direction;

    Map<int, String> clockPositions = {
      0: "12 o'clock",
      1: "1 o'clock",
      2: "2 o'clock",
      3: "3 o'clock",
      4: "4 o'clock",
      5: "5 o'clock",
      6: "6 o'clock",
      7: "7 o'clock",
      8: "8 o'clock",
      9: "9 o'clock",
      10: "10 o'clock",
      11: "11 o'clock",
    };

    return clockPositions[direction] ?? "12 o'clock";
  }

  void _provideNavigation(String beaconId, double distance, int rssi) {
    print(
        'Providing navigation for beacon: $beaconId at distance: $distance meters');

    // Only update voice guidance if enough time has passed
    final now = DateTime.now();
    bool shouldSpeak = now.difference(_lastUpdateTime).inMilliseconds >= 3000;

    // Always update the UI with new distance
    setState(() {
      _navigationStatus = "Distance: ${distance.toStringAsFixed(1)} meters";
    });

    // Reset reached destination flag if user moves away
    if (_hasReachedDestination && distance > 1.5) {
      _hasReachedDestination = false;
    }

    if (shouldSpeak) {
      _lastUpdateTime = now;
      String message = "";

      if (distance < 1 && !_hasReachedDestination) {
        message = "You have reached ${beaconLocations[beaconId]}";
        _hasReachedDestination = true;
        _navigationTimer?.cancel();
      } else if (!_hasReachedDestination) {
        int steps = (distance / 0.75).round();
        String proximity = "";

        if (distance < 3) {
          proximity = "You are very close to ${beaconLocations[beaconId]}. ";
        } else if (distance < 7) {
          proximity =
              "You are getting closer to ${beaconLocations[beaconId]}. ";
        } else {
          proximity = "Continue walking towards ${beaconLocations[beaconId]}. ";
        }

        String clockDirection = _getClockDirection(rssi);
        message =
            "$proximity Turn towards $clockDirection and walk approximately $steps steps. "
            "Distance: ${distance.toStringAsFixed(1)} meters.";
      }

      if (message.isNotEmpty) {
        print('Navigation message: $message');
        _addToSpeechQueue(message);
      }
    }
  }

  void _selectDestination(String beaconId) {
    print('Selected destination: $beaconId');
    setState(() {
      _targetLocation = beaconId;
      _navigationStatus = "Navigating to ${beaconLocations[beaconId]}";
      _lastDistance = 0;
      _lastDirection = 0;
      _hasReachedDestination = false;
      _speechQueue.clear();
      _isSpeaking = false;
    });

    _navigationTimer?.cancel();
    _addToSpeechQueue("Starting navigation to ${beaconLocations[beaconId]}. "
        "Please wait while I scan for the beacon.");
  }

  Future<void> _initializeCamera() async {
    // Request camera permission
    var status = await Permission.camera.request();
    if (status.isDenied) {
      setState(() {
        _navigationStatus =
            "Camera permission is required for object detection";
      });
      return;
    }

    // Get available cameras
    final cameras = await availableCameras();
    if (cameras.isEmpty) {
      setState(() {
        _navigationStatus = "No cameras available";
      });
      return;
    }

    // Initialize camera controller
    _cameraController = CameraController(
      cameras.first,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();
      _objectDetector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );
      setState(() {
        _isCameraInitialized = true;
      });
      _startObjectDetection();
    } catch (e) {
      print('Error initializing camera: $e');
      setState(() {
        _navigationStatus = "Error initializing camera";
      });
    }
  }

  void _startObjectDetection() {
    if (!_isCameraInitialized) return;

    _cameraController!.startImageStream((CameraImage image) {
      if (_objectDetector == null) return;

      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      _objectDetector!.processImage(inputImage).then((objects) {
        if (mounted) {
          setState(() {
            _detectedObjects = objects;
          });
        }
      }).catchError((error) {
        print('Error processing image: $error');
      });
    });
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _navigationTimer?.cancel();
    _scanSubscription?.cancel();
    flutterTts.stop();
    _cameraController?.dispose();
    _objectDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mall Navigation'),
      ),
      body: Column(
        children: [
          // Navigation section (70% of screen)
          Expanded(
            flex: 7,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    _navigationStatus,
                    style: const TextStyle(fontSize: 24),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_foundBeacons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Found beacons: ${_foundBeacons.length}\n${_foundBeacons.join('\n')}",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                if (_targetLocation.isNotEmpty &&
                    _distances.containsKey(_targetLocation))
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(
                      "Current distance: ${_distances[_targetLocation]!.toStringAsFixed(1)} meters",
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 2,
                    padding: const EdgeInsets.all(16.0),
                    children: beaconLocations.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: ElevatedButton(
                          onPressed: () => _selectDestination(entry.key),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.all(20),
                          ),
                          child: Text(
                            entry.value,
                            style: const TextStyle(fontSize: 20),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          // Object detection section (30% of screen)
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.black,
              child: _isCameraInitialized
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_cameraController!),
                        CustomPaint(
                          painter: ObjectDetectorPainter(
                            _detectedObjects,
                            _cameraController!.value.previewSize!,
                          ),
                        ),
                      ],
                    )
                  : const Center(
                      child: Text(
                        'Camera not initialized',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class ObjectDetectorPainter extends CustomPainter {
  final List<DetectedObject> objects;
  final Size previewSize;

  ObjectDetectorPainter(this.objects, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.red;

    for (final object in objects) {
      canvas.drawRect(
        Rect.fromLTWH(
          object.boundingBox.left * size.width / previewSize.width,
          object.boundingBox.top * size.height / previewSize.height,
          object.boundingBox.width * size.width / previewSize.width,
          object.boundingBox.height * size.height / previewSize.height,
        ),
        paint,
      );

      // Draw label
      final TextPainter textPainter = TextPainter(
        text: TextSpan(
          text: object.labels.isNotEmpty ? object.labels.first.text : 'Unknown',
          style: const TextStyle(
            color: Colors.red,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          object.boundingBox.left * size.width / previewSize.width,
          object.boundingBox.top * size.height / previewSize.height - 20,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(ObjectDetectorPainter oldDelegate) {
    return oldDelegate.objects != objects;
  }
}
