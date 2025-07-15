import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/device.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/home.dart';
import 'package:flutter/services.dart';

import 'effect_processor.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) =>
          VisualizerService(), // Create and provide the service
      child: const MyApp(),
    ),
  );
}

const platform = MethodChannel("mic_channel");
final EventChannel micStream = const EventChannel('mic_stream');

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      themeMode: ThemeMode.system,
      home: const VisualizerScreen(),
    );
  }
}

class VisualizerScreen extends StatefulWidget {
  const VisualizerScreen({super.key});

  @override
  State<VisualizerScreen> createState() => _VisualizerScreenState();
}

class _VisualizerScreenState extends State<VisualizerScreen> {
  late VisualizerService _visualizerService;
  int currentPageIndex = 0;
  String selectedEffect = 'linear-fill';
  final List<String> effects = ['linear-fill', 'center-pulse', 'wave-pulse'];

  @override
  void initState() {
    super.initState();
    _visualizerService = Provider.of<VisualizerService>(context, listen: false);
    // Listen to changes in the service's isRunning state to rebuild the FAB
    _visualizerService.addListener(_onVisualizerStateChanged);
    _loadAndSetDevices();
  }

  Future<void> _loadAndSetDevices() async {
    final savedDevices = await loadDevices();
    if (mounted) {
      setState(() {
        _visualizerService.setTargetDevices(savedDevices);
      });
    }
  }

  void _onVisualizerStateChanged() {
    // This will trigger a rebuild if the FAB's appearance depends on isRunning
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _visualizerService.removeListener(_onVisualizerStateChanged);
    // Consider if you want to automatically stop the visualizer when this screen is disposed
    _visualizerService
        .stopVisualizer(); // Or manage its lifecycle more globally
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVisualizerRunning = context.watch<VisualizerService>().isRunning;

    return Scaffold(
      appBar: AppBar(title: const Text("UDP Master")),
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: (int index) {
          setState(() {
            currentPageIndex = index;
          });
        },
        selectedIndex: currentPageIndex,
        destinations: [
          NavigationDestination(
            selectedIcon: Icon(Icons.home),
            icon: Icon(Icons.home_outlined),
            label: "Home",
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.add),
            icon: Icon(Icons.add_outlined),
            label: "New Device",
          ),
        ],
      ),
      body: [Home(), AddDevice()][currentPageIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Before toggling, ensure the service has the latest device list
          // This is a bit redundant if _updateVisualizerServiceDevices is called promptly,
          // but good as a safeguard.
          // _visualizerService.setTargetDevices(devices); // Make sure 'devices' is current

          await _visualizerService.toggleVisualizer();
          // The UI will update automatically if using ChangeNotifier + listener or Provider
        },
        backgroundColor: isVisualizerRunning
            ? Colors.redAccent
            : Theme.of(context).colorScheme.secondary,
        foregroundColor: Colors.white,
        elevation: 2.0,
        shape: const CircleBorder(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: Icon(
            isVisualizerRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(isVisualizerRunning),
            size: 36,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
