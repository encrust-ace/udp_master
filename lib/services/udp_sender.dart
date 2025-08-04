import 'dart:io';

import 'package:udp_master/models.dart';

class UdpSender {
  RawDatagramSocket? _udpSocket; // Persistent UDP sender

  RawDatagramSocket? get udpSocket => _udpSocket;

  Future<void> initiateUDPSender() async {
    // Bind to any port and address.
    _udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  }

  void send(LedDevice device, List<int> buffer) {
    _udpSocket?.send(buffer, InternetAddress(device.ip), device.port,);
  }

  void close() {
    _udpSocket?.close();
    _udpSocket = null; // Clear the instance
  }
}
