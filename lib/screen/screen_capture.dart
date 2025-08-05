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
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;
    final dialogWidth = isLargeScreen ? 700.0 : screenSize.width * 0.9;
    final dialogHeight = isLargeScreen ? 600.0 : screenSize.height * 0.8;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with close button
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Share Your Screen',
                    style: TextStyle(
                      fontSize: isLargeScreen ? 20 : 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close_rounded,
                      color: Colors.grey.shade600,
                      size: 24,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            // Tabs
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TabBar(
                controller: _tabController,
                onTap: _onTabChanged,
                indicator: BoxDecoration(
                  color: Colors.blue.shade600,
                  borderRadius: BorderRadius.circular(10),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey.shade600,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                tabs: const [
                  Tab(text: 'Entire Screen'),
                  Tab(text: 'Application Window'),
                ],
              ),
            ),

            // Content grid
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSourceGrid(isLargeScreen),
              ),
            ),

            // Action buttons
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _selectedSource != null
                        ? () => Navigator.pop(context, _selectedSource)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Share',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceGrid(bool isLargeScreen) {
    final filteredSources = _sources.entries
        .where((entry) => entry.value.type == _sourceType)
        .map((entry) => entry.value)
        .toList();

    if (filteredSources.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.monitor_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No sources available',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    final crossAxisCount = isLargeScreen
        ? (_sourceType == SourceType.Screen ? 2 : 3)
        : (_sourceType == SourceType.Screen ? 1 : 2);

    return GridView.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: isLargeScreen ? 1.4 : 1.2,
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.selected ? Colors.blue.shade600 : Colors.grey.shade300,
            width: widget.selected ? 2 : 1,
          ),
          boxShadow: widget.selected
              ? [
                  BoxShadow(
                    color: Colors.blue.shade200,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade100,
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
                            color: Colors.grey.shade400,
                          ),
                        ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                widget.source.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.selected ? FontWeight.w600 : FontWeight.w500,
                  color: widget.selected ? Colors.blue.shade700 : Colors.grey.shade700,
                ),
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
        final provider = Provider.of<VisualizerProvider>(context, listen: false);
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
        barrierDismissible: false,
        builder: (context) => const ScreenSelectDialog(),
      ).then((source) {
        if (source != null) _startScreenCapture(source);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Screen Capture"),
        backgroundColor: Colors.grey.shade50,
        foregroundColor: Colors.grey.shade800,
        elevation: 0,
      ),
      body: _isScreenCapturing
          ? RepaintBoundary(
              key: videoKey,
              child: SizedBox(
                width: MediaQuery.of(context).size.width,
                height: MediaQuery.of(context).size.height,
                child: RTCVideoView(_localRenderer),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.screen_share_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Ready to share your screen',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the button below to get started',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScreenCapture,
        backgroundColor: _isScreenCapturing ? Colors.red.shade600 : Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 4,
        label: Text(
          _isScreenCapturing ? 'Stop Sharing' : 'Start Sharing',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        icon: Icon(_isScreenCapturing ? Icons.stop_rounded : Icons.play_arrow_rounded),
      ),
    );
  }
}