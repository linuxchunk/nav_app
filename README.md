# Mall Navigation System for Visually Impaired

This project implements an indoor navigation system using BLE beacons to help visually impaired people navigate through a mall. The system consists of two main components:

1. ESP32-based BLE Beacons
2. Flutter Mobile Application

## ESP32 BLE Beacon Setup

### Hardware Requirements
- ESP32 development boards (one for each location)
- USB cables for programming
- Power supplies for the beacons

### Software Requirements
- PlatformIO IDE (recommended) or Arduino IDE
- Required libraries:
  - BLEDevice
  - BLEUtils
  - BLEServer
  - BLEBeacon

### Beacon Setup Instructions
1. Open the ESP32 project in PlatformIO/Arduino IDE
2. For each beacon:
   - Modify the `BEACON_ID` in `main.cpp` to a unique number
   - Upload the code to the ESP32
   - Place the beacon at the designated location in the mall

## Flutter Mobile Application

### Requirements
- Flutter SDK (2.17.0 or higher)
- Android Studio or VS Code with Flutter plugins
- An Android/iOS device with:
  - Bluetooth LE support
  - Location permissions
  - Text-to-speech capabilities

### Setup Instructions
1. Clone this repository
2. Navigate to the `mall_nav_app` directory
3. Run `flutter pub get` to install dependencies
4. Update the `beaconLocations` map in `lib/main.dart` with your beacon UUIDs and locations
5. Build and run the application:
   ```bash
   flutter run
   ```

### Usage
1. Launch the application
2. Grant necessary permissions (Bluetooth, Location)
3. Select your destination from the available buttons
4. Follow the voice instructions to reach your destination
5. The app will provide:
   - Distance information
   - Directional guidance
   - Arrival notifications

## Beacon Placement Guidelines
- Place beacons at key locations (entrances, exits, shops, food court, etc.)
- Mount beacons at a consistent height (recommended: 2.5-3 meters)
- Avoid placing beacons near metal surfaces or other sources of interference
- Ensure beacons have clear line-of-sight where possible
- Space beacons appropriately to maintain coverage

## Security Considerations
- The beacon UUID is hardcoded and should be changed for production use
- Consider implementing encryption for sensitive deployments
- Regularly monitor beacon battery levels and status

## Troubleshooting
- If beacons are not detected:
  - Check if Bluetooth is enabled
  - Verify location permissions are granted
  - Ensure beacons are powered and functioning
- If navigation is inaccurate:
  - Check for interference sources
  - Verify beacon placement
  - Calibrate TX power values if necessary

## Contributing
Contributions are welcome! Please feel free to submit pull requests. 