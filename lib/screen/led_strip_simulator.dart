import 'package:flutter/material.dart';

class LedStripSimulator extends StatelessWidget {
  final List<int> packet;
  final int ledCount;

  const LedStripSimulator({
    super.key,
    required this.packet,
    required this.ledCount,
  });

  @override
  Widget build(BuildContext context) {
    final data = packet.length > 2
        ? packet.sublist(2)
        : List.filled(ledCount * 3, 0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: List.generate(ledCount, (index) {
            final i = index * 3;
            Color color = Colors.black;
            if (i + 2 < data.length) {
              final r = data[i];
              final g = data[i + 1];
              final b = data[i + 2];
              color = Color.fromARGB(255, r, g, b);
            }

            return Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: color, // Use the calculated color
                  shape: BoxShape.circle, // Make it a circle
                ),
              ),
            );
          }).reversed.toList(), // Reversed so LED[0] is at bottom
        );
      },
    );
  }
}
