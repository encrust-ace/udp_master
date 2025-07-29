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
    // Ensure we only compute the necessary RGB data once
    final List<Color> ledColors = List.generate(ledCount, (index) {
      final i = 2 + index * 3;
      if (i + 2 < packet.length) {
        return Color.fromARGB(255, packet[i], packet[i + 1], packet[i + 2]);
      } else {
        return Colors.black;
      }
    });

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: ledColors.reversed.map((color) {
        return const Expanded(
          child: _LedDot(color: Colors.black), // Placeholder, color gets overridden below
        ).copyWithColor(color);
      }).toList(),
    );
  }
}

class _LedDot extends StatelessWidget {
  final Color color;

  const _LedDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0.05),
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

extension on Expanded {
  /// Allows you to override the color of the child `_LedDot`.
  Expanded copyWithColor(Color newColor) {
    return Expanded(
      flex: flex,
      child: _LedDot(color: newColor),
    );
  }
}
