import 'package:flutter/material.dart';

class VolumeBar extends StatelessWidget {
  const VolumeBar({
    super.key,
    required this.currentVolume,
    required this.peakVolume,
  });

  final double currentVolume;
  final double peakVolume;

  Color get _barColor {
    if (currentVolume < 0.3) return Colors.green;
    if (currentVolume < 0.7) return Colors.yellow;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Volum:'),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 20,
            child: LinearProgressIndicator(
              value: currentVolume,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(_barColor),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Volum: ${(currentVolume * 100).toStringAsFixed(1)}%'),
        Text('Peak: ${(peakVolume * 100).toStringAsFixed(1)}%'),
      ],
    );
  }
}
