import 'dart:io';
import 'package:flutter/foundation.dart';

import 'led_effects.dart';
import 'device.dart'; // Your LedDevice model

RawDatagramSocket? _socket;

Future<void> _ensureSocketInitialized() async {
  if (_socket == null) {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (e) {
      if (kDebugMode) {
        // Minimal print for error
        // print("Socket init error: $e");
      }
    }
  }
}

Future<void> sendUdpPacketsToDevices(
  List<LedDevice> targetDevices,
  double volume, // Assumed to be normalized 0.0 - 1.0
) async {
  await _ensureSocketInitialized();
  if (_socket == null) {
    return;
  }

  double currentHue = (DateTime.now().millisecondsSinceEpoch % 36000) / 36000.0;

  for (var device in targetDevices) {
    if (!device.isEnabled) continue;

    LedEffect? effect = getEffectById(device.effect);

    if (effect == null) {
      if (availableEffects.isNotEmpty) {
        effect = availableEffects.first;
      } else {
        continue;
      }
    }

    List<int> packetData = effect.renderFunction(
      deviceIpKey: device.ip, // Use device.ip as the key for stateful effects
      ledCount: device.ledCount,
      volume: volume,
      hue: currentHue,
      // Optional parameters like peakHueOffset, peakDecayMillis, etc.,
      // will be passed as null if not explicitly provided here.
      // The render functions or the lambdas in availableEffects
      // should handle their defaults.
    );

    if (packetData.isNotEmpty && packetData[0] != 0x00) {
      try {
        _socket?.send(packetData, InternetAddress(device.ip), device.port);
      } catch (e) {
        if (kDebugMode) {
          // Minimal print for error
          // print("UDP send error to ${device.ip}: $e");
        }
      }
    }
  }
}

void disposeSocket() {
  _socket?.close();
  _socket = null;
}
