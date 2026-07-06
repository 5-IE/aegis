#include <Arduino.h>
#include <NimBLEDevice.h>

#define BEACON_ADVERTISING_TIME 160 
#define ROTATION_INTERVAL 300 // 5 minutes

NimBLEAdvertising *pAdvertising;
NimBLEAdvertisementData advData;

// Function to update the payload bytes directly
void updateBeaconMinor(uint16_t newMinor) {
    // Standard iBeacon payload is 25 bytes (2 Apple ID + 2 Type/Len + 16 UUID + 2 Major + 2 Minor + 1 Power)
    // The Minor is located at index 22 and 23 of the manufacturer data
    static uint8_t beaconPayload[25] = {
        0x4C, 0x00, 0x02, 0x15,
        0x26, 0xD0, 0x81, 0x4C, 0xF8, 0x1C, 0x4B, 0x2D,  // UUID [1]
        0xAC, 0x57, 0x03, 0x2E, 0x2A, 0xFF, 0x86, 0x42, // UUID [2]
        0x00, 0xF4, // Major (244)
        0x00, 0x00, // Minor (Placeholder)
        0xC5        // Power (-59 dBm)
    };

    beaconPayload[22] = (newMinor >> 8) & 0xFF;
    beaconPayload[23] = newMinor & 0xFF;

    advData.setManufacturerData(std::string((char*)beaconPayload, 25));
    
    // refresh the data without stopping/starting the stack
    if (pAdvertising) {
        pAdvertising->setAdvertisementData(advData);
        pAdvertising->refreshAdvertisingData(); 
    }
}

void setup() {
    Serial.begin(115200);
    NimBLEDevice::init(""); 

    pAdvertising = NimBLEDevice::getAdvertising();
    advData.setFlags(0x1A);
    
    // Initial set
    updateBeaconMinor(0);
    
    pAdvertising->setAdvertisementData(advData);
    pAdvertising->setAdvertisingInterval(BEACON_ADVERTISING_TIME);
    pAdvertising->start();
    
    Serial.println("Beacon active with rotating minor...");
}

void loop() {
    // Simple time-based rotation
    static uint32_t lastRotation = 0;
    uint32_t now = millis() / 1000;
    
    if (now - lastRotation >= ROTATION_INTERVAL) {
        uint16_t newMinor = (now / ROTATION_INTERVAL) % 65535;
        updateBeaconMinor(newMinor);
        lastRotation = now;
        Serial.printf("Minor rotated to: %d\n", newMinor);
    }
    delay(1000);
}