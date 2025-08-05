import 'package:flutter/material.dart';
import 'package:udp_master/models.dart';
import 'package:udp_master/services/visualizer_provider.dart';

class DisplaySyncConfigPage extends StatefulWidget {
  final VisualizerProvider visualizerProvider;
  const DisplaySyncConfigPage({super.key, required this.visualizerProvider});

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

  Future<void> getAvailableSides({DisplayPosition? includeSide}) async {
    List<DisplayPosition> availableSides = DisplayPosition.values.where((side) {
      return !widget.visualizerProvider.displaySides.any(
        (s) => s.position == side,
      );
    }).toList();

    if (includeSide != null && !availableSides.contains(includeSide)) {
      availableSides.add(includeSide);
    }

    setState(() {
      _availableSides = availableSides;
    });
  }

  void initializeData(DisplaySide side, {bool isEditing = false}) {
    setState(() {
      _isEditing = isEditing;
      _startIndexController.text = side.startIndex.toString();
      _endIndexController.text = side.endIndex.toString(); // fixed typo
      _selectedSide = side.position;
      _selectedDevice = side.device;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await getAvailableSides();

      if (_availableSides.isNotEmpty) {
        final defaultDevice = widget.visualizerProvider.devices.firstWhere(
          (device) =>
              device.type == DeviceType.wled ||
              device.type == DeviceType.esphome,
          orElse: () => widget.visualizerProvider.devices.first,
        );

        final defaultSide = DisplaySide(
          position: _availableSides.first,
          startIndex: 1,
          endIndex: defaultDevice.ledCount,
          device: defaultDevice,
        );

        initializeData(defaultSide);
      }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Please select a device')));
      return;
    }

    if (_formKey.currentState!.validate()) {
      final startIndex = int.tryParse(_startIndexController.text);
      final endIndex = int.tryParse(_endIndexController.text);

      if (startIndex == null || endIndex == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Invalid start or end index')));
        return;
      }

      final newSide = DisplaySide(
        position: _selectedSide,
        device: _selectedDevice,
        startIndex: startIndex,
        endIndex: endIndex,
      );

      widget.visualizerProvider.addOrUpdateDisplaySide(newSide);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${newSide.position.name} saved successfully')),
      );

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          ListView.builder(
            shrinkWrap: true,
            itemCount: widget.visualizerProvider.displaySides.length,
            itemBuilder: (context, index) {
              final edge = widget.visualizerProvider.displaySides[index];
              return GestureDetector(
                onTap: () async {
                  // Ensure the edited side is in available sides
                  await getAvailableSides(includeSide: edge.position);

                  // Initialize editing state
                  initializeData(edge, isEditing: true);

                  // Delay the dialog to allow state to update
                  await Future.delayed(Duration(milliseconds: 100));

                  if (!mounted) return;

                  showDialog(
                    barrierDismissible: false,
                    context: context,
                    builder: (_) => addOrEditForm(context),
                  );
                },

                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: [
                        buildRow(Icons.rounded_corner, edge.position.name),
                        buildRow(Icons.light, edge.device?.name ?? ''),
                        buildRow(Icons.join_left, edge.startIndex.toString()),
                        buildRow(Icons.join_right, edge.endIndex.toString()),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          IconButton(
            onPressed: _availableSides.isEmpty
                ? null
                : () {
                    final defaultDevice =
                        widget.visualizerProvider.devices.first;
                    initializeData(
                      DisplaySide(
                        position: _availableSides.first,
                        startIndex: 1,
                        endIndex: defaultDevice.ledCount,
                        device: defaultDevice,
                      ),
                      isEditing: false,
                    );

                    showDialog(
                      barrierDismissible: false,
                      context: context,
                      builder: (_) => addOrEditForm(context),
                    );
                  },
            icon: Icon(Icons.add),
          ),
        ],
      ),
    );
  }

  Row buildRow(IconData icon, String text) {
    return Row(children: [Icon(icon), SizedBox(width: 4), Text(text)]);
  }

  Dialog addOrEditForm(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButtonFormField<DisplayPosition>(
                isExpanded: true,
                hint: const Text("Select Side"),
                value: _availableSides.contains(_selectedSide)
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
                    setState(() {
                      _selectedSide = val;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<LedDevice>(
                isExpanded: true,
                hint: Text("Select Device"),
                value: _selectedDevice,
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
                items: widget.visualizerProvider.devices
                    .map(
                      (device) => DropdownMenuItem(
                        value: device,
                        child: Text(device.name),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedDevice = val;
                    });
                  }
                },
              ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startIndexController,
                      decoration: InputDecoration(
                        labelText: "Start Index",
                        hintText: "1",
                        prefixIcon: Icon(Icons.join_left),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        final end =
                            int.tryParse(_endIndexController.text) ??
                            _selectedDevice?.ledCount ??
                            1;
                        if (n == null ||
                            n <= 0 ||
                            n > (_selectedDevice?.ledCount ?? 1) ||
                            n > end) {
                          return 'Invalid start index';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _endIndexController,
                      decoration: InputDecoration(
                        labelText: "End Index",
                        hintText: "1",
                        prefixIcon: Icon(Icons.join_right),
                        border: const OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        final n = int.tryParse(value ?? '');
                        final start =
                            int.tryParse(_startIndexController.text) ?? 1;
                        if (n == null ||
                            n <= 0 ||
                            n > (_selectedDevice?.ledCount ?? 1) ||
                            n < start) {
                          return 'Invalid end index';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: const Text("Cancel"),
                    ),
                  ),
                  const SizedBox(width: 8),
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
