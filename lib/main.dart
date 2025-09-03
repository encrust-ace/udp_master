import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:udp_master/screen/effects.dart';
import 'package:udp_master/screen/home.dart';
import 'package:udp_master/screen/simulator_page.dart';
import 'package:udp_master/services/discover.dart';
import 'services/visualizer_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => VisualizerProvider(),
      child: const MyApp(),
    ),
  );
}

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<VisualizerProvider>(context, listen: false);
      provider.initiateTheAppData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<VisualizerProvider>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Icon(Icons.lightbulb, size: 36),
        actions: [
          IconButton(
            onPressed: () async => await provider.toggleVisualizer(),
            icon: Selector<VisualizerProvider, bool>(
              selector: (_, p) => p.isRunning,
              builder: (_, isRunning, __) => Icon(
                isRunning ? Icons.pause_circle : Icons.play_arrow_rounded,
                size: 28,
              ),
            ),
          ),
          IconButton(
            onPressed: provider.importDevicesFromJsonFile,
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: () => provider.exportDevicesToJsonFile(context),
            icon: const Icon(Icons.upload),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      DeviceScanPage(visualizerProvider: provider),
                ),
              );
            },
            icon: const Icon(Icons.search),
          ),
          const SizedBox(width: 16),
        ],
      ),
      resizeToAvoidBottomInset: true,

      bottomNavigationBar: Selector<VisualizerProvider, int>(
        selector: (_, p) => p.currentSelectedTab,
        builder: (_, selectedIndex, __) => NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: provider.setCurrentSelectedTab,
          destinations: const [
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
      ),

      body: Selector<VisualizerProvider, int>(
        selector: (_, p) => p.currentSelectedTab,
        builder: (context, selectedIndex, _) {
          return IndexedStack(
            index: selectedIndex,
            children: [Home(), EffectsPage(), SimulatorPage()],
          );
        },
      ),
    );
  }
}
