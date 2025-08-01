import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';
import 'package:webview_flutter/webview_flutter.dart';

class DeviceDetails extends StatefulWidget {
  final LedDevice device;
  const DeviceDetails({super.key, required this.device});

  @override
  State<DeviceDetails> createState() => _DeviceDetailsState();
}

class _DeviceDetailsState extends State<DeviceDetails> {
  WebViewController _controller = WebViewController();
  void _initializeWebView() {
    // Initialize the WebView controller here if needed
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate())
      ..loadRequest(Uri.parse('http://${widget.device.ip}'));
  }

  @override
  void initState() {
    _initializeWebView();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Details')),
      body: WebViewWidget(controller: _controller),
    );
  }
}
