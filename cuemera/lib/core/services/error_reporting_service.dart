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

  final String? context;
}

class ErrorReportingService {
  ErrorReportingService._();

  static final ErrorReportingService instance = ErrorReportingService._();

  static const int _maxRetained = 200;
  final List<ErrorReport> _recentReports = [];

  List<ErrorReport> get recentReports => List.unmodifiable(_recentReports);

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
  }

  void reportFlutterError(FlutterErrorDetails details) {
    report(
      details.exception,
      details.stack ?? StackTrace.empty,
      context: details.context?.toString() ?? 'FlutterError',
    );
  }
}
