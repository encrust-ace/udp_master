import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/home.dart';
import 'package:flutter/services.dart';

import 'effect_processor.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) =>
          VisualizerService(),
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
  bool _isInitialDependenciesMet = false;
  int currentPageIndex = 0;
  String selectedEffect = 'linear-fill';
  final List<String> effects = ['linear-fill', 'center-pulse', 'wave-pulse'];


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialDependenciesMet) {
      _visualizerService = Provider.of<VisualizerService>(context, listen: true);
      _visualizerService.loadAndSetInitialDevices();
      // Or, if you need to watch it for this screen:
      // final service = context.watch<VisualizerService>();
      // service.loadAndSetInitialDevices();
      _isInitialDependenciesMet = true;
    }
  }


  @override
  Widget build(BuildContext context) {
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
      body: [Home(visualizerService: _visualizerService), AddDevice()][currentPageIndex],
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await _visualizerService.toggleVisualizer();
        },
        backgroundColor: _visualizerService.isRunning
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
            _visualizerService.isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(_visualizerService.isRunning),
            size: 36,
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }
}
