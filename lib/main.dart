import 'package:flutter/material.dart';
import 'package:udp_master/device.dart';
import 'package:udp_master/screen/add_device.dart';
import 'package:udp_master/screen/home.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

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
  int currentPageIndex = 0;
  String selectedEffect = 'linear-fill';
  final List<String> effects = ['linear-fill', 'center-pulse', 'wave-pulse'];
  List<LedDevice> devices = [];

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
      body: [Home(), AddDevice()][currentPageIndex],
    );
  }
}
