import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/screen/effects.dart';
import 'package:udp_master/screen/home.dart';
import 'package:udp_master/screen/simulator_page.dart';
import 'package:udp_master/services/discover.dart';

import 'visualizer_provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => VisualizerProvider(),
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
  late VisualizerProvider _visualizerProvider;
  bool _isInitialDependenciesMet = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialDependenciesMet) {
      _visualizerProvider = Provider.of<VisualizerProvider>(
        context,
        listen: false,
      );
      _visualizerProvider.initiateTheAppData();
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
            iconSize: 36,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      DeviceScanPage(visualizerProvider: _visualizerProvider),
                ),
              );
            },
            icon: Icon(Icons.search),
          ),

          const SizedBox(width: 16),
        ],
      ),
      resizeToAvoidBottomInset: true,

      // Bottom Navigation Bar
      bottomNavigationBar: Consumer<VisualizerProvider>(
        builder: (_, provider, __) => NavigationBar(
          selectedIndex: provider.currentSelectedTab,
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

      // Body using IndexedStack to avoid rebuilds
      body: Consumer<VisualizerProvider>(
        builder: (context, provider, _) => IndexedStack(
          index: provider.currentSelectedTab,
          children: [
            Home(visualizerProvider: provider),
            EffectsPage(visualizerProvider: provider),
            SimulatorPage(visualizerProvider: provider),
          ],
        ),
      ),

      // Floating action button
      floatingActionButton: Consumer<VisualizerProvider>(
        builder: (context, provider, _) => FloatingActionButton(
          onPressed: () async => await provider.toggleVisualizer(),
          backgroundColor: provider.isRunning
              ? Colors.redAccent
              : Theme.of(context).colorScheme.secondary,
          foregroundColor: Colors.white,
          elevation: 2.0,
          shape: const CircleBorder(),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) =>
                ScaleTransition(scale: animation, child: child),
            child: Icon(
              provider.isRunning
                  ? Icons.stop_rounded
                  : Icons.play_arrow_rounded,
              key: ValueKey<bool>(provider.isRunning),
              size: 36,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniEndFloat,
    );
  }
}
