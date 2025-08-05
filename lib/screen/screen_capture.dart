import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_background/flutter_background.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class ScreenSelectDialog extends StatefulWidget {
  const ScreenSelectDialog({super.key});

  @override
  State<ScreenSelectDialog> createState() => _ScreenSelectDialogState();
}

class _ScreenSelectDialogState extends State<ScreenSelectDialog>
    with TickerProviderStateMixin {
  final Map<String, DesktopCapturerSource> _sources = {};
  SourceType _sourceType = SourceType.Screen;
  DesktopCapturerSource? _selectedSource;
  final List<StreamSubscription<DesktopCapturerSource>> _subscriptions = [];
  Timer? _timer;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.delayed(const Duration(milliseconds: 100), _getSources);
    _subscriptions.addAll([
      desktopCapturer.onAdded.stream.listen((source) {
        _sources[source.id] = source;
        if (mounted) setState(() {});
      }),
      desktopCapturer.onRemoved.stream.listen((source) {
        _sources.remove(source.id);
        if (mounted) setState(() {});
      }),
      desktopCapturer.onThumbnailChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tabController.dispose();
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _getSources() async {
    try {
      final sources = await desktopCapturer.getSources(types: [_sourceType]);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 3), (_) {
        desktopCapturer.updateSources(types: [_sourceType]);
      });

      setState(() {
        _sources.clear();
        for (var source in sources) {
          _sources[source.id] = source;
        }
      });
    } catch (e) {
      debugPrint('Error getting sources: $e');
    }
  }

  void _onTabChanged(int index) {
    final newType = index == 0 ? SourceType.Screen : SourceType.Window;
    if (_sourceType != newType) {
      _sourceType = newType;
      _selectedSource = null;
      _getSources();
    }
  }

  @override
  Widget build(BuildContext context) {
      return AlertDialog(
        title: const Text('Share Your Screen'),
        contentPadding: const EdgeInsets.all(24.0),
        actionsPadding: const EdgeInsets.all(8),
        content: SizedBox(
        width: 700.0,
        height: 600.0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                onTap: _onTabChanged,
                tabs: const [
                  Tab(text: 'Entire Screen'),
                  Tab(text: 'Application Window'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildSourceGrid()),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
          ElevatedButton(
            onPressed: _selectedSource != null
                ? () => Navigator.of(context).pop(_selectedSource)
                : null,
            child: const Text('Share'),
          ),
        ],
      );
  }

  Widget _buildSourceGrid() {
    final filteredSources = _sources.entries
        .where((entry) => entry.value.type == _sourceType)
        .map((entry) => entry.value)
        .toList();

    if (filteredSources.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.monitor_outlined, size: 48),
            SizedBox(height: 16),
            Text('No sources available'),
          ],
        ),
      );
    }

    final crossAxisCount = _sourceType == SourceType.Screen ? 2 : 3;

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.4,
      ),
      itemCount: filteredSources.length,
      itemBuilder: (context, index) {
        final source = filteredSources[index];
        return ThumbnailWidget(
          source: source,
          selected: _selectedSource?.id == source.id,
          onTap: (source) => setState(() => _selectedSource = source),
        );
      },
    );
  }
}

class ThumbnailWidget extends StatefulWidget {
  final DesktopCapturerSource source;
  final bool selected;
  final Function(DesktopCapturerSource) onTap;

  const ThumbnailWidget({
    super.key,
    required this.source,
    required this.selected,
    required this.onTap,
  });

  @override
  State<ThumbnailWidget> createState() => _ThumbnailWidgetState();
}

class _ThumbnailWidgetState extends State<ThumbnailWidget> {
  final List<StreamSubscription> _subscriptions = [];
  Uint8List? _thumbnail;

  @override
  void initState() {
    super.initState();
    _subscribeToSource();
  }

  void _subscribeToSource() {
    _subscriptions.addAll([
      widget.source.onThumbnailChanged.stream.listen((thumbnail) {
        if (mounted) setState(() => _thumbnail = thumbnail);
      }),
      widget.source.onNameChanged.stream.listen((_) {
        if (mounted) setState(() {});
      }),
    ]);
  }

  @override
  void didUpdateWidget(covariant ThumbnailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source.id != widget.source.id) {
      for (var sub in _subscriptions) {
        sub.cancel();
      }
      _subscriptions.clear();
      _subscribeToSource();
    }
  }

  @override
  void dispose() {
    for (var sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => widget.onTap(widget.source),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: widget.selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).hoverColor,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _thumbnail != null
                      ? Image.memory(
                          _thumbnail!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                        )
                      : Center(
                          child: Icon(
                            widget.source.type == SourceType.Screen
                                ? Icons.monitor_outlined
                                : Icons.window_outlined,
                            size: 32,
                            color: Theme.of(context).disabledColor,
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                widget.source.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScreenCapturePage extends StatefulWidget {
  const ScreenCapturePage({super.key});

  @override
  State<ScreenCapturePage> createState() => _ScreenCapturePageState();
}

class _ScreenCapturePageState extends State<ScreenCapturePage> {
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isScreenCapturing = false;
  final GlobalKey videoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _localRenderer.initialize();
  }

  @override
  void dispose() {
    _stop();
    _localRenderer.dispose();
    super.dispose();
  }

  Future<void> _startScreenCapture(DesktopCapturerSource? source) async {
    try {
      var stream = await navigator.mediaDevices.getDisplayMedia(
        <String, dynamic>{
          'video': source == null
              ? true
              : {
                  'deviceId': {'exact': source.id},
                  'mandatory': {'frameRate': 30.0},
                },
        },
      );

      stream.getVideoTracks()[0].onEnded = () {
        debugPrint('Screen sharing ended.');
      };

      _localStream = stream;
      _localRenderer.srcObject = stream;

      final provider = Provider.of<VisualizerProvider>(context, listen: false);
      await provider.startScreenSync(stream, videoKey);

      if (mounted) setState(() => _isScreenCapturing = true);
    } catch (e) {
      debugPrint('Error starting screen capture: $e');
    }
  }

  Future<void> _stop() async {
    try {
      if (kIsWeb) {
        _localStream?.getTracks().forEach((track) => track.stop());
      }
      await _localStream?.dispose();
      _localStream = null;
      _localRenderer.srcObject = null;

      if (mounted) {
        final provider = Provider.of<VisualizerProvider>(context, listen: false);
        await provider.stopScreenSync();
      }
    } catch (e) {
      debugPrint('Error stopping screen capture: $e');
    }
  }

  Future<void> _toggleScreenCapture() async {
    if (_isScreenCapturing) {
      await _stop();
      if (mounted) setState(() => _isScreenCapturing = false);
    } else if (WebRTC.platformIsDesktop) {
      showDialog<DesktopCapturerSource>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const ScreenSelectDialog(),
      ).then((source) {
        if (source != null) _startScreenCapture(source);
      });
    } else {
      if (WebRTC.platformIsAndroid) {
        Future<void> requestBackgroundPermission([bool isRetry = false]) async {
          try {
            var hasPermissions = await FlutterBackground.hasPermissions;
            if (!isRetry) {
              const androidConfig = FlutterBackgroundAndroidConfig(
                notificationTitle: 'Screen Sharing',
                notificationText: 'LiveKit Example is sharing the screen.',
                notificationImportance: AndroidNotificationImportance.normal,
                notificationIcon: AndroidResource(
                  name: 'livekit_ic_launcher',
                  defType: 'mipmap',
                ),
              );
              hasPermissions = await FlutterBackground.initialize(androidConfig: androidConfig);
            }
            if (hasPermissions && !FlutterBackground.isBackgroundExecutionEnabled) {
              await FlutterBackground.enableBackgroundExecution();
            }
          } catch (e) {
            if (!isRetry) {
              await Future<void>.delayed(const Duration(seconds: 1));
              await requestBackgroundPermission(true);
            }
            debugPrint('Could not enable background mode: $e');
          }
        }

        await requestBackgroundPermission();
      }

      await _startScreenCapture(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Screen Capture"), elevation: 0),
      body: _isScreenCapturing
          ? RepaintBoundary(
              key: videoKey,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: RTCVideoView(_localRenderer),
              ),
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.screen_share_outlined, size: 64),
                  SizedBox(height: 24),
                  Text('Ready to share your screen'),
                  SizedBox(height: 8),
                  Text('Tap the button below to get started'),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleScreenCapture,
        child: Icon(
          _isScreenCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        ),
      ),
    );
  }
}
