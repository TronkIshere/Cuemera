// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/service_locator.dart';
import 'core/services/memory_service.dart';
import 'core/services/theme_preference_service.dart';
import 'core/theme/app_theme.dart';
// import 'features/goal_selection/presentation/screens/goal_selection_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupLocator();
  await sl<MemoryService>().init();

  final container = ProviderContainer();
  await container.read(themeModeProvider.notifier).load();

  runApp(UncontrolledProviderScope(container: container, child: const MyApp()));
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
      // home: const GoalSelectionScreen(),
    );
  }
}
