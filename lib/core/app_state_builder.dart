// ─────────────────────────────────────────────────────────────────────────────
// app_state_builder.dart
// FIX 6: Drop-in replacement for the addListener + setState({}) pattern.
//
// WHY:  The old pattern rebuilds the ENTIRE screen widget tree on every
//       AppState change — even if only one card at the bottom needs updating.
//       ListenableBuilder scopes the rebuild to only the widgets wrapped
//       inside it.
//
// HOW:  Wrap only the part of the UI that actually reads AppState data.
//       Everything outside the builder (AppBar, search field, etc.) is
//       unaffected and never rebuilds.
//
// USAGE:
//   // Old pattern — remove initState/dispose listener boilerplate
//   AppStateBuilder(
//     builder: (context, state) {
//       return Text('${state.totalOrders} orders');
//     },
//   )
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'app_state.dart';

/// Rebuilds [builder] whenever [AppState] notifies listeners.
/// Scopes rebuilds to only the returned subtree — not the entire screen.
class AppStateBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, AppState state) builder;

  const AppStateBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState(),
      builder: (context, _) => builder(context, AppState()),
    );
  }
}
