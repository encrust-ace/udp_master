import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/effects.dart';
import 'package:udp_master/screen/home.dart';
import 'package:flutter/services.dart';
import 'package:udp_master/screen/simulator_page.dart';

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
  int currentPageIndex = 2;
  bool isVisualizer = false;

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
        title: const Icon(Icons.lightbulb, size: 36),
        actions: [
          IconButton(
            onPressed: () async {
              showDialog(
                barrierDismissible: false,
                useSafeArea: true,
                context: context,
                builder: (BuildContext context) {
                  return Dialog(
                    child: AddDevice(visualizerProvider: _visualizerProvider),
                  );
                },
              );
            },
            icon: Icon(Icons.add, size: 36),
          ),
          SizedBox(width: 16),
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
            selectedIcon: Icon(Icons.animation),
            icon: Icon(Icons.animation_outlined),
            label: "Effects",
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.strikethrough_s_sharp),
            icon: Icon(Icons.strikethrough_s_sharp),
            label: "Simulator",
          ),
        ],
      ),
      body: [
        Home(visualizerProvider: _visualizerProvider),
        EffectsPage(visualizerProvider: _visualizerProvider),
        SimulatorPaage(visualizerProvider: _visualizerProvider,)
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
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    );
  }
}
