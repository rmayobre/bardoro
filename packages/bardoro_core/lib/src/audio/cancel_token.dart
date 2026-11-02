// SPDX-License-Identifier: GPL-3.0-or-later

/// Cooperative cancellation: the runner checks [isCancelled] between chunks, and anything long-running (an
/// ffmpeg process, an HTTP request) registers a callback to be stopped immediately.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  /// Returns a function that removes the listener.
  void Function() onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class CancelledException implements Exception {
  const CancelledException();

  @override
  String toString() => 'Cancelled';
}
