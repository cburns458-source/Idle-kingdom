import 'package:flutter/material.dart';

import '../theme.dart';

/// Covers the game while unattended catch-up is applied or presented.
class ReturningOverlay extends StatelessWidget {
  const ReturningOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xCC120C08),
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Palette.gold),
              SizedBox(height: 18),
              Text(
                'Returning to your adventure…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
