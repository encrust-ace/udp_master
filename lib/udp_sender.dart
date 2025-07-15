import 'dart:io';
import 'dart:typed_data';
import 'led_effects.dart';
import 'device.dart';

Future<void> sendUdpPacketsToDevices(
  List<LedDevice> devices,
  double volume,
) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  double hue = (DateTime.now().millisecondsSinceEpoch * 0.0001) % 1.0;

  for (final device in devices) {
    List<int> data;
    switch (device.currentEffect) {
      case 'linear-fill':
        data = renderLinearFillPacket(
          ledCount: device.ledCount,
          volume: volume,
          hue: hue,
        );
        break;
      // Add more effects here as needed
      default:
        data = renderLinearFillPacket(
          ledCount: device.ledCount,
          volume: volume,
          hue: hue,
        );
    }

    socket.send(
      Uint8List.fromList(data),
      InternetAddress(device.ip),
      device.port,
    );
  }
  socket.close();
}