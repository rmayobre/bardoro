// SPDX-License-Identifier: GPL-3.0-or-later
import 'package:flutter/widgets.dart';
import 'package:zero_nads/zero_nads.dart';

/// Rebuilds whenever a zero_nads [Snapshot] changes.
class SnapshotBuilder<T extends Object> extends StatelessWidget {
  const SnapshotBuilder({super.key, required this.snapshot, required this.builder});

  final Snapshot<T> snapshot;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) => StreamBuilder<T>(
    stream: snapshot.collect(),
    initialData: snapshot.value,
    // Always read the current value: a change can land between build and subscription.
    builder: (context, _) => builder(context, snapshot.value),
  );
}
