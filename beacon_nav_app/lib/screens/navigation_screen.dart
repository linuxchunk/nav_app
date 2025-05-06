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
  int _scanAttempts = 0;
  static const int MAX_SCAN_ATTEMPTS = 3;

  // Beacon Locations (example MAC addresses and names)
  final Map<String, String> beaconLocations = {
    "24:DC:C3:45:90:D6": "Hospital Entrance",
    "E8:68:EA:F6:BE:90": "Pharmacy",
    "30:C6:F7:28:E9:40": "Patient Ward",
    "24:6F:28:15:8D:9C": "Emergency Room",
  };

  // Additional map to store the reverse mapping for UI display
  Map<String, String> _beaconDisplayMap = {};

  @override
  void initState() {
    super.initState();
    _initializeBeaconDisplayMap();
    _initializeTts();
    _checkBluetoothState();
  }

  void _initializeBeaconDisplayMap() {
    // Create reverse mapping for display purposes
    _beaconDisplayMap = Map.fromEntries(
      beaconLocations.entries.map(
        (entry) => MapEntry(entry.key, entry.value),
      ),
    );
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
    if (!_isSpeaking) {
      _processNextSpeech();
    }
  }

  Future<void> _checkBluetoothState() async {
    try {
      // Check availability
      FlutterBluePlus.adapterState.listen((state) {
        if (state == BluetoothAdapterState.on) {
          _startScanning();
        } else {
          setState(() {
            _navigationStatus = "Please turn on Bluetooth";
          });
          _addToSpeechQueue(
              "Bluetooth is not enabled. Please turn on Bluetooth to continue.");
        }
      });

      // Initial check
      if (await FlutterBluePlus.isAvailable == false) {
        setState(() {
          _navigationStatus = "Bluetooth not available on this device";
        });
        return;
      }

      if (await FlutterBluePlus.isOn == false) {
        setState(() {
          _navigationStatus = "Please turn on Bluetooth";
        });
        _addToSpeechQueue(
            "Bluetooth is not enabled. Please turn on Bluetooth to continue.");
        // Request to enable Bluetooth if possible
        await FlutterBluePlus.turnOn();
        return;
      }

      _startScanning();
    } catch (e) {
      print('Error checking Bluetooth state: $e');
      setState(() {
        _navigationStatus = "Error: $e";
      });
    }
  }

  void _startScanning() async {
    // Cancel any existing subscription
    await _scanSubscription?.cancel();
    
    setState(() {
      _isScanning = true;
      _navigationStatus = "Scanning for beacons...";
      _scanAttempts = 0;
    });

    try {
      // Make sure we're not already scanning
      if (await FlutterBluePlus.isScanning.first) {
        await FlutterBluePlus.stopScan();
      }
      
      // Start listening for scan results
      _scanSubscription = FlutterBluePlus.scanResults.listen(
        (results) {
          for (ScanResult result in results) {
            String deviceId = result.device.id.toString();
            String deviceName = result.device.name;
            
            // Debug log
            print('Found device: $deviceId, Name: $deviceName, RSSI: ${result.rssi}');
            
            // Check if this is a beacon we're interested in
            String? locationName;
            
            // First check if it's in our predefined map by MAC address
            if (beaconLocations.containsKey(deviceId)) {
              locationName = beaconLocations[deviceId];
            } 
            // Then check by device name patterns
            else if (deviceName.isNotEmpty) {
              if (deviceName == "Mall_Entrance") {
                locationName = "Mall Entrance";
                // Add to our display map for UI consistency
                _beaconDisplayMap[deviceId] = locationName;
              } else if (deviceName.contains("Beacon")) {
                // Try to determine location from beacon name
                if (deviceName.contains("Entrance")) {
                  locationName = "Hospital Entrance";
                } else if (deviceName.contains("Pharmacy")) {
                  locationName = "Pharmacy";
                } else if (deviceName.contains("Ward")) {
                  locationName = "Patient Ward";
                } else if (deviceName.contains("Emergency")) {
                  locationName = "Emergency Room";
                } else {
                  // Generic name for unknown beacons
                  locationName = "Beacon ${deviceName.replaceAll('Beacon', '').trim()}";
                }
                // Add to our display map
                _beaconDisplayMap[deviceId] = locationName;
              }
            }
            
            // Only process if we identified this as a beacon of interest
            if (locationName != null) {
              double distance = _calculateDistance(
                  result.rssi, result.advertisementData.txPowerLevel ?? -59);
              
              setState(() {
                _distances[deviceId] = distance;
                _lastRssi[deviceId] = result.rssi;
                if (!_foundBeacons.contains(deviceId)) {
                  _foundBeacons.add(deviceId);
                  print('New beacon found: $deviceId, Name: $locationName');
                }
              });

              if (_targetLocation == deviceId) {
                _provideNavigation(deviceId, distance, result.rssi);
              }
            }
          }
        },
        onError: (error) {
          print('Scan error: $error');
          _restartScan();
        },
      );

      // Start the scan with simplified parameters
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidScanMode: AndroidScanMode.lowLatency,
      ).then((_) {
        // After timeout, restart scan if we haven't found any beacons
        if (_foundBeacons.isEmpty) {
          _restartScan();
        }
      }).catchError((e) {
        print('Error starting scan: $e');
        _restartScan();
      });

    } catch (e) {
      print('Exception during scanning: $e');
      _restartScan();
    }
  }
  
  void _restartScan() {
    _scanAttempts++;
    print('Restart scan attempt: $_scanAttempts');

    if (_scanAttempts >= MAX_SCAN_ATTEMPTS) {
      setState(() {
        _navigationStatus =
            "Unable to find beacons. Please check your Bluetooth connection.";
        _isScanning = false;
      });
      _addToSpeechQueue(
          "Unable to find beacons. Please ensure the beacons are powered on and nearby.");

      // Try again after a delay
      Future.delayed(Duration(seconds: 10), () {
        if (mounted) {
          _scanAttempts = 0;
          _startScanning();
        }
      });
    } else {
      // Small delay before restarting scan
      Future.delayed(Duration(seconds: 2), () {
        if (mounted) {
          _startScanning();
        }
      });
    }
  }

  double _calculateDistance(int rssi, int txPower) {
    if (rssi == 0) return -1;

    // Enhanced distance calculation based on the log-distance path loss model
    if (rssi >= txPower) {
      return 0.1; // Very close
    }

    double ratio = rssi * 1.0 / txPower;
    if (ratio < 1.0) {
      return pow(ratio, 10.0).toDouble();
    } else {
      double accuracy = (0.89976) * pow(ratio, 7.7095) + 0.111;

      // Apply minimum and maximum bounds
      if (accuracy < 0.1) return 0.1;
      if (accuracy > 30.0) return 30.0;

      return accuracy;
    }
  }

  String _getClockDirection(int rssi) {
    int lastRssi = _lastRssi[_targetLocation] ?? rssi;
    int difference = rssi - lastRssi;
    int direction;

    // More sensitive direction detection
    if (difference > 3) {
      // Signal getting stronger - keep current direction
      direction = _lastDirection;
    } else if (difference < -3) {
      // Signal getting weaker - suggest turning around
      direction = (_lastDirection + 6) % 12; // 180 degree turn
    } else {
      // Small change - keep current direction but suggest small adjustment
      direction = (_lastDirection + (difference < 0 ? 1 : 0)) % 12;
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

    // Use our display map to get the proper location name
    String locationName = _beaconDisplayMap[beaconId] ?? "Unknown Location";

    setState(() {
      _navigationStatus = "Distance to $locationName: ${distance.toStringAsFixed(1)} meters";
    });

    if (_hasReachedDestination && distance > 1.5) {
      _hasReachedDestination = false;
    }

    if (shouldSpeak) {
      _lastUpdateTime = now;
      String message = "";

      if (distance < 1 && !_hasReachedDestination) {
        message = "You have reached $locationName";
        _hasReachedDestination = true;
        _navigationTimer?.cancel();
      } else if (!_hasReachedDestination) {
        int steps = (distance / 0.75).round();
        String proximity = "";

        if (distance < 3) {
          proximity = "You are very close to $locationName. ";
        } else if (distance < 7) {
          proximity = "You are getting closer to $locationName. ";
        } else {
          proximity = "Continue walking towards $locationName. ";
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
    // Use our display map to get the proper location name
    String locationName = _beaconDisplayMap[beaconId] ?? "Unknown Location";
    
    setState(() {
      _targetLocation = beaconId;
      _navigationStatus = "Navigating to $locationName";
      _lastDistance = 0;
      _lastDirection = 0;
      _hasReachedDestination = false;
      _speechQueue.clear();
      _isSpeaking = false;
    });

    _navigationTimer?.cancel();
    _addToSpeechQueue("Starting navigation to $locationName. "
        "Please wait while I scan for the beacon.");

    // Make sure we're scanning for beacons
    if (!_isScanning) {
      _startScanning();
    }
  }

  @override
  void dispose() {
    _scanTimer?.cancel();
    _navigationTimer?.cancel();
    _scanSubscription?.cancel();
    FlutterBluePlus.stopScan();
    flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hospital Navigation'),
        actions: [
          IconButton(
            icon: Icon(_isScanning
                ? Icons.bluetooth_searching
                : Icons.bluetooth_disabled),
            onPressed: () {
              if (_isScanning) {
                FlutterBluePlus.stopScan();
                setState(() {
                  _isScanning = false;
                  _navigationStatus = "Scanning paused";
                });
              } else {
                _startScanning();
              }
            },
          ),
        ],
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
              child: Column(
                children: [
                  Text(
                    "Found beacons: ${_foundBeacons.length}",
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  ...List.generate(_foundBeacons.length, (index) {
                    String beaconId = _foundBeacons[index];
                    double distance = _distances[beaconId] ?? 0.0;
                    // Use our display map for proper names
                    String locationName = _beaconDisplayMap[beaconId] ?? "Unknown Beacon";
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        "$locationName: ${distance.toStringAsFixed(1)}m",
                        style: const TextStyle(fontSize: 16),
                      ),
                    );
                  }),
                ],
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
                      backgroundColor:
                          _targetLocation == entry.key ? Colors.green : null,
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
      floatingActionButton: FloatingActionButton(
        onPressed: _startScanning,
        tooltip: 'Rescan for beacons',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}