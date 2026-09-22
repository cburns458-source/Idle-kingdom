import 'package:flutter/widgets.dart';

/// Marks a subtree as sitting behind a page that covers it.
///
/// A covered location stays mounted, because its scroll offset and open rows are
/// worth keeping for the player's return, but nothing in it can be seen. The
/// parts of it that follow the frame clock read this and hold still until the
/// page closes, which is itself a change here and so rebuilds them.
class OutOfSight extends InheritedWidget {
  const OutOfSight({super.key, required this.hidden, required super.child});

  final bool hidden;

  static bool of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<OutOfSight>()?.hidden ?? false;
  }

  @override
  bool updateShouldNotify(OutOfSight oldWidget) => hidden != oldWidget.hidden;
}
