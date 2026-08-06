// core/services/error_reporting_service.dart
import 'package:flutter/foundation.dart';

/// A single captured error/crash event.
class ErrorReport {
  const ErrorReport({
    required this.error,
    required this.stackTrace,
    required this.timestamp,
    this.context,
  });

  final String error;
  final String stackTrace;
  final DateTime timestamp;

  /// Where the error came from (e.g. 'reference_image_analyzer: pose
  /// detection', 'FlutterError', 'PlatformDispatcher', 'runZonedGuarded').
  final String? context;
}

/// Centralized error/crash reporting.
///
/// Today this only retains recent reports in memory and prints them via
/// `debugPrint` (visible in `flutter run`/`flutter logs`, not just in
/// debug builds). It is the single place every silent `catch` in the app
/// should report through, so that:
///  - swapping in a real remote sink (Firebase Crashlytics, Sentry, a
///    custom backend, ...) later is a one-file change, not a grep-and-edit
///    across every service, and
///  - the app has *a* record of what went wrong even before that remote
///    sink exists.
///
/// Wiring a real remote sink is a product decision (which service, which
/// account/API keys) and is intentionally left as a TODO below rather than
/// picked unilaterally.
class ErrorReportingService {
  ErrorReportingService._();

  static final ErrorReportingService instance = ErrorReportingService._();

  static const int _maxRetained = 200;
  final List<ErrorReport> _recentReports = [];

  /// Most recent reports, oldest first. Capped at [_maxRetained] entries
  /// so this can't grow unbounded over a long session.
  List<ErrorReport> get recentReports => List.unmodifiable(_recentReports);

  /// Report a caught error. Call this from any `catch` block that would
  /// otherwise be silent, instead of (or in addition to) `debugPrint`.
  void report(Object error, StackTrace stackTrace, {String? context}) {
    final entry = ErrorReport(
      error: error.toString(),
      stackTrace: stackTrace.toString(),
      timestamp: DateTime.now(),
      context: context,
    );

    _recentReports.add(entry);
    if (_recentReports.length > _maxRetained) {
      _recentReports.removeAt(0);
    }

    debugPrint(
      '[ErrorReportingService]'
      '${context != null ? ' [$context]' : ''} $error\n$stackTrace',
    );

    // TODO(remote-sink): once a crash-reporting service is chosen
    // (Crashlytics, Sentry, etc.), forward `entry` to it here. Until then,
    // reports are local-only and cleared on app restart.
  }

  /// Wire this to `FlutterError.onError` in `main()` to capture framework
  /// (widget build/layout/paint) errors that would otherwise only show a
  /// red error screen.
  void reportFlutterError(FlutterErrorDetails details) {
    report(
      details.exception,
      details.stack ?? StackTrace.empty,
      context: details.context?.toString() ?? 'FlutterError',
    );
  }
}
