import 'package:udp/udp.dart';

class UdpSender {
  UDP? _udpInstance; // Persistent UDP sender

  UDP? get udpInstance => _udpInstance;

  Future<void> initiateUDPSender() async {
    _udpInstance = await UDP.bind(Endpoint.any());
  }

  void close() {
    _udpInstance?.close();
    _udpInstance = null; // Clear the instance
  }
}
