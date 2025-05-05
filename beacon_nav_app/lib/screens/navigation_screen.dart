import 'dart:async';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';


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

  // Beacon Locations (example MAC addresses and names)
  final Map<String, String> beaconLocations = {
    "24:DC:C3:45:90:D6": "Mall Entrance",
    "E8:68:EA:F6:BE:90": "Mall Exit",
  };

  @override
  void initState() {
    super.initState();
    _initializeTts();
    _checkBluetoothState();
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

  Future<void> _checkBluetoothState() async {
    bool isAvailable = await FlutterBluePlus.isAvailable;
    bool isOn = await FlutterBluePlus.isOn;

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

  void _startScanning() async {
    await _scanSubscription?.cancel();

    setState(() {
      _isScanning = true;
      _navigationStatus = "Scanning for beacons...";
    });

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult result in results) {
        String deviceId = result.device.id.toString();
        if (beaconLocations.containsKey(deviceId)) {
          double distance = _calculateDistance(
              result.rssi, result.advertisementData.txPowerLevel ?? -59);
          setState(() {
            _distances[deviceId] = distance;
            _lastRssi[deviceId] = result.rssi;
            if (!_foundBeacons.contains(deviceId)) {
              _foundBeacons.add(deviceId);
            }
          });

          if (_targetLocation == deviceId) {
            _provideNavigation(deviceId, distance, result.rssi);
          }
        }
      }
    });

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
    final now = DateTime.now();
    bool shouldSpeak = now.difference(_lastUpdateTime).inMilliseconds >= 3000;

    setState(() {
      _navigationStatus = "Distance: ${distance.toStringAsFixed(1)} meters";
    });

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
        _addToSpeechQueue(message);
      }
    }
  }

  void _selectDestination(String beaconId) {
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

  @override
  void dispose() {
    _scanTimer?.cancel();
    _navigationTimer?.cancel();
    _scanSubscription?.cancel();
    flutterTts.stop();
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
    );
  }
}