import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

/// Opt-in timing marks for development and homologation builds.
/// No identifiers, credentials, URLs or response bodies are recorded.
class PerformanceTrace {
  PerformanceTrace._();

  static const bool enabled = bool.fromEnvironment(
    'ACADEMYHUB_PERF_TRACE',
    defaultValue: false,
  );

  static final Stopwatch _clock = Stopwatch()..start();

  static void mark(String stage) {
    if (!enabled) return;
    final elapsedMs = _clock.elapsedMicroseconds / 1000;
    debugPrint(
        '[AcademyHubPerf] stage=$stage tMs=${elapsedMs.toStringAsFixed(1)}');
    developer.Timeline.instantSync(
      'AcademyHubPerf:$stage',
      arguments: {'tMs': elapsedMs},
    );
  }

  static Future<T> measure<T>(String stage, Future<T> Function() action) async {
    if (!enabled) return action();
    final timer = Stopwatch()..start();
    mark('$stage.start');
    try {
      return await action();
    } finally {
      timer.stop();
      debugPrint(
        '[AcademyHubPerf] stage=$stage durationMs=${(timer.elapsedMicroseconds / 1000).toStringAsFixed(1)}',
      );
      mark('$stage.end');
    }
  }
}
