import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class DisplaySyncConfigPage extends StatefulWidget {
  const DisplaySyncConfigPage({super.key});

  @override
  State<DisplaySyncConfigPage> createState() => _DisplaySyncConfigPageState();
}

class _DisplaySyncConfigPageState extends State<DisplaySyncConfigPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late DisplayPosition _selectedSide;
  LedDevice? _selectedDevice;

  final TextEditingController _startIndexController = TextEditingController(
    text: '1',
  );
  final TextEditingController _endIndexController = TextEditingController(
    text: '1',
  );

  List<DisplayPosition> _availableSides = [];
  bool _isEditing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAvailableSides();
  }

  Future<void> _loadAvailableSides({DisplayPosition? includeSide}) async {
    final provider = context.read<VisualizerProvider>();

    List<DisplayPosition> availableSides = DisplayPosition.values.where((side) {
      return !provider.displaySides.any((s) => s.position == side);
    }).toList();

    if (includeSide != null && !availableSides.contains(includeSide)) {
      availableSides.add(includeSide);
    }

    if (!mounted) return;
    setState(() => _availableSides = availableSides);

    if (_availableSides.isNotEmpty &&
        _selectedDevice == null &&
        provider.devices.isNotEmpty) {
      final defaultDevice = provider.devices.firstWhere(
        (device) =>
            device.type == DeviceType.wled || device.type == DeviceType.esphome,
        orElse: () => provider.devices.first,
      );

      initializeData(
        DisplaySide(
          position: _availableSides.first,
          startIndex: 1,
          endIndex: defaultDevice.ledCount,
          device: defaultDevice,
        ),
      );
    }
  }

  void initializeData(DisplaySide side, {bool isEditing = false}) {
    setState(() {
      _isEditing = isEditing;
      _selectedSide = side.position;
      _selectedDevice = side.device;
      _startIndexController.text = side.startIndex.toString();
      _endIndexController.text = side.endIndex.toString();
    });
  }

  @override
  void dispose() {
    _startIndexController.dispose();
    _endIndexController.dispose();
    super.dispose();
  }

  void _saveDisplaySide() {
    if (_selectedDevice == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a device')));
      return;
    }

    if (_formKey.currentState!.validate()) {
      final startIndex = int.tryParse(_startIndexController.text);
      final endIndex = int.tryParse(_endIndexController.text);

      if (startIndex == null || endIndex == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid start or end index')),
        );
        return;
      }

      final newSide = DisplaySide(
        position: _selectedSide,
        device: _selectedDevice,
        startIndex: startIndex,
        endIndex: endIndex,
      );

      context.read<VisualizerProvider>().addOrUpdateDisplaySide(newSide);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${newSide.position.name} saved successfully')),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualizerProvider>();

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: provider.displaySides.length,
              itemBuilder: (context, index) {
                final edge = provider.displaySides[index];

                return GestureDetector(
                  onTap: () async {
                    final localContext = context;

                    await _loadAvailableSides(includeSide: edge.position);
                    initializeData(edge, isEditing: true);

                    if (!localContext.mounted) return;

                    showDialog(
                      context: localContext,
                      barrierDismissible: false,
                      builder: (_) => _buildAddEditDialog(localContext),
                    );
                  },
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        spacing: 8,
                        children: [
                          _buildRow(Icons.rounded_corner, edge.position.name),
                          _buildRow(Icons.light, edge.device?.name ?? ''),
                          _buildRow(
                            Icons.join_left,
                            edge.startIndex.toString(),
                          ),
                          _buildRow(Icons.join_right, edge.endIndex.toString()),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _availableSides.isEmpty
                ? null
                : () {
                    final localContext = context;
                    final defaultDevice = provider.devices.first;

                    initializeData(
                      DisplaySide(
                        position: _availableSides.first,
                        startIndex: 1,
                        endIndex: defaultDevice.ledCount,
                        device: defaultDevice,
                      ),
                      isEditing: false,
                    );

                    if (!localContext.mounted) return;

                    showDialog(
                      context: localContext,
                      barrierDismissible: false,
                      builder: (_) => _buildAddEditDialog(localContext),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Row _buildRow(IconData icon, String text) {
    return Row(
      spacing: 4,
      children: [Icon(icon), const SizedBox(width: 4), Text(text)]);
  }

  Dialog _buildAddEditDialog(BuildContext context) {
    final provider = context.read<VisualizerProvider>();

    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            spacing: 24,
            children: [
              DropdownButtonFormField<DisplayPosition>(
                isExpanded: true,
                hint: const Text("Select Side"),
                initialValue: _availableSides.contains(_selectedSide)
                    ? _selectedSide
                    : null,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 8,
                  ),
                ),
                items: _availableSides
                    .map(
                      (side) =>
                          DropdownMenuItem(value: side, child: Text(side.name)),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedSide = val);
                  }
                },
              ),
              DropdownButtonFormField<LedDevice>(
                isExpanded: true,
                hint: const Text("Select Device"),
                initialValue: _selectedDevice,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 9,
                    horizontal: 8,
                  ),
                ),
                items: provider.devices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device,
                        child: Text(device.name),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _selectedDevice = val);
                  }
                },
              ),
              Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startIndexController,
                      decoration: const InputDecoration(
                        labelText: "Start Index",
                        hintText: "1",
                        prefixIcon: Icon(Icons.join_left),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        final end =
                            int.tryParse(_endIndexController.text) ??
                            _selectedDevice?.ledCount ??
                            1;
                        if (n == null || n <= 0 || n > end) {
                          return 'Invalid start index';
                        }
                        return null;
                      },
                    ),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _endIndexController,
                      decoration: const InputDecoration(
                        labelText: "End Index",
                        hintText: "1",
                        prefixIcon: Icon(Icons.join_right),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        final start =
                            int.tryParse(_startIndexController.text) ?? 1;
                        final max = _selectedDevice?.ledCount ?? 1;
                        if (n == null || n < start || n > max) {
                          return 'Invalid end index';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              Row(
                spacing: 12,
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveDisplaySide,
                      child: Text(_isEditing ? "Save" : "Add"),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
