// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/services/error_reporting_service.dart';
import 'core/services/supabase_service.dart';
import 'core/services/theme_preference_service.dart';
import 'core/theme/app_theme.dart';
import 'features/splash/presentation/screens/splash_screen.dart';

void main() {
  FlutterError.onError = (details) {
    ErrorReportingService.instance.reportFlutterError(details);
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    ErrorReportingService.instance.report(
      error,
      stackTrace,
      context: 'PlatformDispatcher',
    );
    return true;
  };

  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await SupabaseService.initialize();
      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stackTrace) {
      ErrorReportingService.instance.report(
        error,
        stackTrace,
        context: 'runZonedGuarded',
      );
    },
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cuemera',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      home: const SplashScreen(),
    );
  }
}
