import 'package:flutter/material.dart';

import '../session/game_controller.dart';
import 'action_stage.dart';

/// The running activity: combat, gathering, or a craft queue, drawn as the
/// two-column stage that sits in the location dock.
class ActivityPanel extends StatelessWidget {
  const ActivityPanel({super.key, required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) => ActionStage(controller: controller);
}
