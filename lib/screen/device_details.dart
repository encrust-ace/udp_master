import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:udp_master/models.dart';

class DeviceDetails extends StatefulWidget {
  final LedDevice device;
  const DeviceDetails({super.key, required this.device});

  @override
  State<DeviceDetails> createState() => _DeviceDetailsState();
}

class _DeviceDetailsState extends State<DeviceDetails> {
  InAppWebViewController? webViewController;
  String url = "";

  @override
  void initState() {
    url = 'http://${widget.device.ip}';
    //' widget.device.ip;
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Web View')),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        onWebViewCreated: (controller) {
          webViewController = controller;
        },
        onLoadStart: (controller, url) {
          print("Started loading: $url");
        },
        onLoadStop: (controller, url) {
          print("Finished loading: $url");
        },
      ),
    );
  }
}
