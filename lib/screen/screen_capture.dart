import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class ScreenSelectDialog extends StatefulWidget {
  const ScreenSelectDialog({super.key});

  @override
  State<ScreenSelectDialog> createState() => _ScreenSelectDialogState();
}

class _ScreenSelectDialogState extends State<ScreenSelectDialog> {
  final Map<String, DesktopCapturerSource> _sources = {};
  SourceType _sourceType = SourceType.Screen;
  DesktopCapturerSource? _selectedSource;
  final List<StreamSubscription<DesktopCapturerSource>> _subscriptions = [];
  Timer? _timer;

  @override
  void initState() {
    super.initState();
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
      _getSources();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Choose what to share',
                  style: TextStyle(fontSize: 16),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
      
          // Content with tabs
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: DefaultTabController(
                length: 2,
                child: Column(
                  children: [
                    TabBar(
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.black54,
                      onTap: _onTabChanged,
                      tabs: const [
                        Tab(text: 'Entire Screen'),
                        Tab(text: 'Window'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildSourceGrid(SourceType.Screen, 2),
                          _buildSourceGrid(SourceType.Window, 3),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      
          // Action buttons
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _selectedSource),
                  child: const Text('Share'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceGrid(SourceType type, int crossAxisCount) {
    final filteredSources = _sources.entries
        .where((entry) => entry.value.type == type)
        .map((entry) => entry.value)
        .toList();

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
      child: Column(
        children: [
          Expanded(
            child: Container(
              decoration: widget.selected
                  ? BoxDecoration(
                      border: Border.all(width: 2, color: Colors.blueAccent),
                    )
                  : null,
              child: _thumbnail != null
                  ? Image.memory(
                      _thumbnail!,
                      gaplessPlayback: true,
                      fit: BoxFit.cover,
                    )
                  : Container(color: Colors.grey.shade200),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.source.name,
            style: TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
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

  Future<void> _startScreenCapture(DesktopCapturerSource source) async {
    try {
      final stream = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'deviceId': {'exact': source.id},
          'mandatory': {'frameRate': 30.0},
        },
      });

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
        final provider = Provider.of<VisualizerProvider>(
          context,
          listen: false,
        );
        await provider.stopScreenSync();
      }
    } catch (e) {
      debugPrint('Error stopping screen capture: $e');
    }
  }

  void _toggleScreenCapture() {
    if (_isScreenCapturing) {
      _stop();
      setState(() => _isScreenCapturing = false);
    } else if (WebRTC.platformIsDesktop) {
      showDialog<DesktopCapturerSource>(
        context: context,
        builder: (context) => const ScreenSelectDialog(),
      ).then((source) {
        if (source != null) _startScreenCapture(source);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Screen Capture")),
      body: _isScreenCapturing
          ? RepaintBoundary(
              key: videoKey,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: RTCVideoView(_localRenderer),
              ),
            )
          : const Center(child: Text('Tap the button to start screen capture')),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleScreenCapture,
        tooltip: _isScreenCapturing ? 'Stop' : 'Start',
        child: Icon(_isScreenCapturing ? Icons.call_end : Icons.phone),
      ),
    );
  }
}
