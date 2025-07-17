import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/home.dart';
import 'package:flutter/services.dart';

import 'visualizer_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => VisualizerProvider(),
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
  late VisualizerProvider _visualizerProvider;
  bool _isInitialDependenciesMet = false;
  int currentPageIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialDependenciesMet) {
      _visualizerProvider = Provider.of<VisualizerProvider>(
        context,
        listen: true,
      );
      _visualizerProvider.loadDevices();
      // Or, if you need to watch it for this screen:
      // final service = context.watch<VisualizerService>();
      // service.loadAndSetInitialDevices();
      _isInitialDependenciesMet = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("UDP Master"),
        actions: [
          Row(
            spacing: 16,
            children: [
              ElevatedButton(
                onPressed: () {
                  _visualizerProvider.exportDevicesToJsonFile(context);
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: Text("Export Devices"),
              ),
              SizedBox(width: 8),
              // Text(
              //   _visualizerProvider.castMode == CastMode.video
              //       ? "Video"
              //       : "Audio",
              // ),
              // Switch(
              //   padding: EdgeInsets.only(right: 50),
              //   value: _visualizerProvider.castMode == CastMode.video,
              //   thumbColor: const WidgetStatePropertyAll<Color>(Colors.black),
              //   onChanged: (bool value) {
              //     if (value) {
              //       _visualizerProvider.castMode = CastMode.video;
              //     } else {
              //       _visualizerProvider.castMode = CastMode.audio;
              //     }
              //   },
              // ),
            ],
          ),
        ],
      ),
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
      body: [
        Home(visualizerProvider: _visualizerProvider),
        AddDevice(visualizerProvider: _visualizerProvider),
      ][currentPageIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _visualizerProvider.toggleVisualizer();
        },
        backgroundColor: _visualizerProvider.isRunning
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
            _visualizerProvider.isRunning
                ? Icons.stop_rounded
                : Icons.play_arrow_rounded,
            key: ValueKey<bool>(_visualizerProvider.isRunning),
            size: 36,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
