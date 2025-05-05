#include "sys/time.h"
#include "BLEDevice.h"
#include "BLEUtils.h"
#include "BLEServer.h"
#include "BLEBeacon.h"
#include "esp_sleep.h"

// Mall Navigation Beacon UUID - matches the one from Flutter app
#define BEACON_UUID "87b99b2c-95ff-11ee-b9d1-0242ac120002" // Mall Entrance beacon

// Beacon power settings
#define TX_POWER -59  // Transmission power in dBm, used for distance calculation
#define BEACON_NAME "Mall_Entrance"  // Beaco n name - helpful for debugging

// RTC variables that persist through deep sleep
RTC_DATA_ATTR static time_t last;        // remember last boot in RTC Memory
RTC_DATA_ATTR static uint32_t bootcount; // remember number of boots in RTC Memory

// BLE Advertisement object
BLEAdvertising *pAdvertising;

// Time tracking
struct timeval now;

// Configure the beacon data
void setBeacon() {
  BLEBeacon oBeacon = BLEBeacon();
  
  // Set manufacturer ID (Apple's ID for iBeacon compatibility)
  oBeacon.setManufacturerId(0x4C00); 
  
  // Set the UUID that identifies this specific beacon location
  oBeacon.setProximityUUID(BLEUUID(BEACON_UUID));
  
  // Set Major and Minor values - can be used to differentiate beacons with same UUID
  oBeacon.setMajor(1);  // Major value to identify beacon group
  oBeacon.setMinor(1);  // Minor value to identify specific beacon
  
  // Set measured power (Tx Power) - used for distance calculations
  oBeacon.setSignalPower(TX_POWER);
  
  // Configure advertisement data
  BLEAdvertisementData oAdvertisementData = BLEAdvertisementData();
  BLEAdvertisementData oScanResponseData = BLEAdvertisementData();
  
  // Set flags
  oAdvertisementData.setFlags(0x04); // BR_EDR_NOT_SUPPORTED 0x04
  
  // Set complete name in scan response
  oScanResponseData.setName(BEACON_NAME);
  
  // Prepare service data directly as a String
  String strServiceData = "";
  strServiceData += (char)26;     // Length of data
  strServiceData += (char)0xFF;   // Type (Manufacturer specific data)
  
  // Get beacon data and append it directly to the String
  String beaconData = oBeacon.getData();
  strServiceData += beaconData;
  
  // Set advertisement and scan response data
  oAdvertisementData.addData(strServiceData);
  pAdvertising->setAdvertisementData(oAdvertisementData);
  pAdvertising->setScanResponseData(oScanResponseData);
}

void setup() {
  // Initialize serial communication
  Serial.begin(115200);
  
  // Get current time
  gettimeofday(&now, NULL);
  
  // Log boot information
  Serial.printf("Starting Mall Navigation Beacon %d\n", bootcount++);
  Serial.printf("Boot time: %lds since last reset\n", now.tv_sec);
  last = now.tv_sec;
  
  // Initialize BLE device
  BLEDevice::init(BEACON_NAME);
  
  // Get advertising object
  pAdvertising = BLEDevice::getAdvertising();
  
  // Set up beacon configurations
  setBeacon();
  
  // Set advertising interval (in ms)
  pAdvertising->setMinInterval(0x20); // 20ms * 0.625 = 32ms
  pAdvertising->setMaxInterval(0x40); // 40ms * 0.625 = 64ms
  
  // Start advertising and never stop
  pAdvertising->start();
  Serial.println("Beacon advertising started and will run continuously...");
}

void loop() {
  // Periodically update the console to show the beacon is still running
  Serial.println("Beacon is active and advertising...");
  delay(60000); // Log message every minute
  
  // You could optionally implement a "heartbeat" LED indicator here
  // digitalWrite(LED_PIN, HIGH);
  // delay(100);
  // digitalWrite(LED_PIN, LOW);
}