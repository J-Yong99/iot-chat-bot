import 'package:flutter/material.dart';

class BotAvatar extends StatelessWidget {
  const BotAvatar({super.key});

  @override
  Widget build(BuildContext context) {
    const haBlue = Color(0xFF41BDF5); // Home Assistant 색상

    return CircleAvatar(
      radius: 18,  // 크기 조정
      backgroundColor: haBlue,
      child: const Text(
        'HA',
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
