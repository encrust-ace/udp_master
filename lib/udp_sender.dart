import 'dart:io';
import 'package:flutter/foundation.dart';

import 'led_effects.dart';
import 'device.dart';

RawDatagramSocket? _socket;

Future<void> _ensureSocketInitialized() async {
  if (_socket == null) {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      if (kDebugMode) {
        print("Error initializing socket: $e");
      }
    }
  }
}

Future<void> sendUdpPacketsToDevices(
  List<LedDevice> targetDevices,
  double volume,
) async {
  await _ensureSocketInitialized();
  if (_socket == null) {
    if (kDebugMode) {
      print("UDP Socket not initialized. Cannot send packets.");
    }
    return;
  }

  double currentHue = (DateTime.now().millisecondsSinceEpoch % 3600) / 3600.0;
  for (var device in targetDevices) {
    if (!device.isEnabled) continue;

    LedEffect? effect = getEffectById(
      device.effect,
    ); // Get effect by ID stored in device
    if (effect == null) {
      if (kDebugMode) {
        print(
          "Warning: Effect with ID '${device.effect}' not found for device ${device.name}. Skipping.",
        );
      }
      continue;
    }

    // Call the specific render function for the selected effect
    List<int> packetData = effect.renderFunction(
      ledCount: device.ledCount,
      volume: volume,
      hue: currentHue, // Pass necessary parameters
    );

    try {
      _socket?.send(packetData, InternetAddress(device.ip), device.port);
    } catch (e) {
      if (kDebugMode) {
        print("Error sending UDP packet to ${device.ip}:${device.port}: $e");
      }
    }
  }
}

// Call this when your app is closing or visualizer stops permanently
void disposeSocket() {
  _socket?.close();
  _socket = null;
}
