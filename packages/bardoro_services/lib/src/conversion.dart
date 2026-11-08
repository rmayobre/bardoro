// SPDX-License-Identifier: GPL-3.0-or-later
import 'dart:async';

import 'package:bardoro_core/bardoro_core.dart';
import 'package:volley/volley.dart';
import 'package:zero_nads/zero_nads.dart';

import 'conversion_progress.dart';

// ---------------------------------------------------------------------------------------------------------
// Messages (volley requires every message to implement `Message`). They only carry plain data, so they cross
// the isolate boundary unchanged.
// ---------------------------------------------------------------------------------------------------------

/// Everything the worker isolate needs to run one conversion.
final class ConversionRequest implements Message {
  const ConversionRequest({
    required this.job,
    required this.kokoroUrl,
    this.ffmpeg = 'ffmpeg',
    this.ffprobe = 'ffprobe',
  });

  final PipelineJob job;
  final String kokoroUrl;
  final String ffmpeg;
  final String ffprobe;
}

sealed class ConversionCommand implements Message {
  const ConversionCommand();
}

final class StartConversion extends ConversionCommand {
  const StartConversion(this.request);

  final ConversionRequest request;
}

/// Ask for the events produced since the last poll.
final class PollConversion extends ConversionCommand {
  const PollConversion();
}

final class CancelConversion extends ConversionCommand {
  const CancelConversion();
}

final class ConversionReply implements Message {
  const ConversionReply(this.events, {required this.running});

  final List<PipelineEvent> events;

  /// False once the run has ended and every event has been handed over.
  final bool running;
}

// ---------------------------------------------------------------------------------------------------------
// Worker side (runs inside the volley actor's isolate)
// ---------------------------------------------------------------------------------------------------------

final class _ActiveRun {
  _ActiveRun(this.cancel, this.engine);

  final CancelToken cancel;
  final KokoroHttpEngine engine;
  final List<PipelineEvent> buffer = [];
  bool running = true;
}

// Isolate-local state: each actor has its own copy of this library's globals.
_ActiveRun? _run;

/// The actor's reducer. It must be top-level (volley sends it to the new isolate) and it must return quickly:
/// an actor handles one message at a time, so the pipeline itself runs as an unawaited future on the actor
/// isolate's event loop while [PollConversion] and [CancelConversion] stay answerable.
Future<ConversionReply> conversionReducer(ConversionCommand command) async {
  switch (command) {
    case StartConversion(:final request):
      final active = _run;
      if (active != null && active.running) {
        return const ConversionReply([], running: true);
      }
      _startRun(request);
      return const ConversionReply([], running: true);
    case PollConversion():
      final active = _run;
      if (active == null) return const ConversionReply([], running: false);
      final events = List<PipelineEvent>.of(active.buffer);
      active.buffer.clear();
      return ConversionReply(events, running: active.running);
    case CancelConversion():
      _run?.cancel.cancel();
      return ConversionReply(const [], running: _run?.running ?? false);
  }
}

void _startRun(ConversionRequest request) {
  final engine = KokoroHttpEngine(request.kokoroUrl);
  final run = _ActiveRun(CancelToken(), engine);
  _run = run;
  final runner = PipelineRunner(
    request.job,
    engine: engine,
    ffmpeg: FfmpegService(ffmpeg: request.ffmpeg, ffprobe: request.ffprobe),
    cancel: run.cancel,
  );
  runner.run().listen(
    run.buffer.add,
    onError: (Object e, StackTrace _) =>
        run.buffer.add(Failed('Unexpected error: $e')),
    onDone: () {
      run.running = false;
      unawaited(engine.dispose());
    },
  );
}

// ---------------------------------------------------------------------------------------------------------
// UI side
// ---------------------------------------------------------------------------------------------------------

/// Runs conversions off the UI isolate and exposes their progress as a zero_nads [Snapshot].
///
/// One session per conversion screen. Typical use:
///
/// ```dart
/// final session = ConversionSession();
/// session.progress.collect().listen(render);
/// await session.start(request);
/// ...
/// await session.dispose();
/// ```
final class ConversionSession implements Disposable {
  ConversionSession({this.pollInterval = const Duration(milliseconds: 250)});

  final Duration pollInterval;

  /// Current state of the run. Emits a new value for every pipeline event.
  final Snapshot<ConversionProgress> progress = Snapshot(
    const ConversionProgress(),
  );

  Actor<ConversionReply, ConversionCommand>? _actor;
  Future<void> _tail = Future.value();
  Future<void>? _loop;
  bool _disposed = false;

  /// Completes when the current run has ended (any outcome). Completes immediately if nothing is running.
  Future<void> get finished => _loop ?? Future.value();

  bool get isRunning => progress.value.isActive;

  /// Starts the worker isolate and the run. Returns once the run is underway; follow [progress] for the rest.
  /// Failing to start (for example no isolate) lands in [progress] as a failed phase instead of throwing.
  Future<void> start(ConversionRequest request) async {
    check(!_disposed, () => 'ConversionSession is disposed');
    check(!isRunning, () => 'A conversion is already running');
    progress.value = progress.value.started();
    final started = await Result.runAsync<Unit>(() async {
      final actor_ = await actor<ConversionReply, ConversionCommand>(
        conversionReducer,
      );
      _actor = actor_;
      await _call(StartConversion(request));
      return Unit.instance;
    });
    started.onFailure((e) {
      progress.value = progress.value.apply(Failed('Could not start the conversion worker: $e'));
      unawaited(_shutdown());
    });
    if (started.isSuccess) _loop = _poll();
  }

  Future<void> _poll() async {
    try {
      while (true) {
        await Future<void>.delayed(pollInterval);
        if (_disposed) return;
        final reply = await _call(const PollConversion());
        for (final e in reply.events) {
          progress.value = progress.value.apply(e);
        }
        if (!reply.running) break;
      }
    } catch (e) {
      if (!_disposed && !progress.value.isTerminal) {
        progress.value = progress.value.apply(Failed('Conversion worker stopped: $e'));
      }
    } finally {
      await _shutdown();
    }
  }

  /// Stops after the current step. Finished chapters and chunks stay on disk, so starting again resumes.
  Future<void> cancel() async {
    if (_actor == null || !isRunning) return;
    await _call(const CancelConversion());
  }

  /// Requests are serialised (volley replies arrive in send order), so one in-flight call at a time keeps
  /// each reply matched to its request.
  Future<ConversionReply> _call(ConversionCommand command) {
    final actor_ = _actor;
    if (actor_ == null) return Future.error(StateError('no worker'));
    final reply = _tail.then((_) async {
      final next = actor_.channel.messages.first;
      actor_.channel.send(command);
      return Future.any<ConversionReply>([
        next,
        actor_.closed.then<ConversionReply>(
          (e) => throw StateError(e == null ? 'worker closed' : '$e'),
        ),
      ]);
    });
    _tail = reply.then<void>((_) {}, onError: (Object _) {});
    return reply;
  }

  Future<void> _shutdown() async {
    final actor_ = _actor;
    _actor = null;
    if (actor_ != null) await actor_.dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _shutdown();
  }
}

/// Placeholder success value for [Result]s that carry no data.
final class Unit {
  const Unit._();
  static const Unit instance = Unit._();
}
