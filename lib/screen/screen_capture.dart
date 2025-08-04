import 'dart:core';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/screen_selector.dart';
import 'package:udp_master/services/visualizer_provider.dart';

/*
 * getDisplayMedia sample
 */
class ScreenCapturePage extends StatefulWidget {
  static String tag = 'get_display_media_sample';

  const ScreenCapturePage({super.key});

  @override
  State<ScreenCapturePage> createState() => _ScreenCapturePageState();
}

class _ScreenCapturePageState extends State<ScreenCapturePage> {
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _inCalling = false;
  DesktopCapturerSource? selectedSource;
  final GlobalKey videoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    initRenderers();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (_inCalling) {
      _stop();
    }
    _localRenderer.dispose();
  }

  Future<void> initRenderers() async {
    await _localRenderer.initialize();
  }

  Future<void> selectScreenSourceDialog(BuildContext context) async {
    if (WebRTC.platformIsDesktop) {
      final source = await showDialog<DesktopCapturerSource>(
        context: context,
        builder: (context) => ScreenSelectDialog(),
      );
      if (source != null) {
        await _makeCall(source);
      }
    }
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> _makeCall(DesktopCapturerSource? source) async {
    setState(() {
      selectedSource = source;
    });

    try {
      var stream = await navigator.mediaDevices.getDisplayMedia(
        <String, dynamic>{
          'video': selectedSource == null
              ? true
              : {
                  'deviceId': {'exact': selectedSource!.id},
                  'mandatory': {'frameRate': 30.0},
                },
        },
      );
      stream.getVideoTracks()[0].onEnded = () {
        if (kDebugMode) {
          print(
            'By adding a listener on onEnded you can: 1) catch stop video sharing on Web',
          );
        }
      };

      _localStream = stream;
      _localRenderer.srcObject = _localStream;

      final provider = Provider.of<VisualizerProvider>(context, listen: false);
      await provider.startScreenSync(_localStream!, videoKey);
    } catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
    }
    if (!mounted) return;

    setState(() {
      _inCalling = true;
    });
  }

  Future<void> _stop() async {
    try {
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localStream = null;
      _localRenderer.srcObject = null;
      final provider = Provider.of<VisualizerProvider>(context, listen: false);
      await provider.stopScreenSync();
    } catch (e) {
      if (kDebugMode) {
        print(e.toString());
      }
    }
  }

  Future<void> _hangUp() async {
    await _stop();
    setState(() {
      _inCalling = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Screen Capture"), actions: []),
      body: OrientationBuilder(
        builder: (context, orientation) {
          return Center(
            child: Container(
              width: MediaQuery.of(context).size.width,
              color: Colors.white10,
              child: Stack(
                children: <Widget>[
                  if (_inCalling)
                    RepaintBoundary(
                      key: videoKey,
                      child: Container(
                        margin: EdgeInsets.fromLTRB(0.0, 0.0, 0.0, 0.0),
                        width: MediaQuery.of(context).size.width,
                        height: MediaQuery.of(context).size.height,
                        decoration: BoxDecoration(color: Colors.black54),
                        child: RTCVideoView(_localRenderer),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _inCalling ? _hangUp() : selectScreenSourceDialog(context);
        },
        tooltip: _inCalling ? 'Hangup' : 'Call',
        child: Icon(_inCalling ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
