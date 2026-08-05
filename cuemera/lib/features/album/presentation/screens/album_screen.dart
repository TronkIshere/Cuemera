// features/album/presentation/screens/album_screen.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_spacing.dart';
import '../../../../core/constants/app_typography.dart';
import '../../../../shared/widgets/primary_button.dart';
import '../../../../shared/widgets/score_badge.dart';
import '../../domain/models/shot.dart';
import '../../providers/album_providers.dart';

class AlbumScreen extends ConsumerWidget {
  const AlbumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final album = ref.watch(albumStateProvider);
    final notifier = ref.read(albumStateProvider.notifier);

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text('Album', style: AppTypography.heading2(colors)),
      ),
      body: album.shots.isEmpty
          ? _EmptyState(colors: colors)
          : SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diversity: ${(notifier.diversityScore() * 100).round()}%',
                    style: AppTypography.body(
                      colors,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Try next: ${notifier.suggestNextShotType()}',
                    style: AppTypography.caption(colors),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(AppSpacing.md),
                itemCount: album.shots.length,
                gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: 0.8,
                ),
                itemBuilder: (context, index) {
                  final shot = album.shots[index];
                  return _ShotTile(shot: shot, colors: colors);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_camera_outlined,
              size: 48,
              color: colors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No shots yet',
              style: AppTypography.body(
                colors,
              ).copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Back to camera',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDeleteDialog(
    BuildContext context,
    AppColors colors,
    ) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.surface,
      title: Text('Delete this shot?', style: AppTypography.heading2(colors)),
      content: Text(
        'This removes it from the album and deletes the saved file.',
        style: AppTypography.body(colors),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text('Cancel', style: AppTypography.body(colors)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            'Delete',
            style: AppTypography.body(colors).copyWith(color: colors.warning),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}

class _ShotTile extends ConsumerWidget {
  const _ShotTile({required this.shot, required this.colors});

  final Shot shot;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => ShotDetailScreen(shot: shot)));
      },
      onLongPress: () async {
        final confirmed = await _confirmDeleteDialog(context, colors);
        if (confirmed) {
          await ref.read(albumStateProvider.notifier).removeShot(shot.id);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.textMuted.withOpacity(0.15)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            shot.imagePath != null
                ? Image.file(File(shot.imagePath!), fit: BoxFit.cover)
                : Container(color: colors.surface),
            Positioned(
              bottom: AppSpacing.sm,
              left: AppSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.background.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  shot.shotType,
                  style: AppTypography.caption(colors),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: ScoreBadge(score: shot.score.overall, size: 40),
            ),
          ],
        ),
      ),
    );
  }
}

class ShotDetailScreen extends ConsumerWidget {
  const ShotDetailScreen({super.key, required this.shot});

  final Shot shot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>()!;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: Text(shot.shotType, style: AppTypography.heading2(colors)),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline, color: colors.warning),
            onPressed: () async {
              final confirmed = await _confirmDeleteDialog(context, colors);
              if (confirmed) {
                await ref.read(albumStateProvider.notifier).removeShot(shot.id);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              flex: 3,
              child: shot.imagePath != null
                  ? Image.file(
                File(shot.imagePath!),
                fit: BoxFit.cover,
                width: double.infinity,
              )
                  : Container(color: colors.surface),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ScoreBadge(score: shot.score.overall, size: 56),
                        const SizedBox(width: AppSpacing.md),
                        Text('Overall', style: AppTypography.heading2(colors)),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Expanded(
                      child: GridView.builder(
                        gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: AppSpacing.sm,
                          mainAxisSpacing: AppSpacing.sm,
                          childAspectRatio: 1.0,
                        ),
                        itemCount: shot.score.breakdown.length,
                        itemBuilder: (context, index) {
                          final entry = shot.score.breakdown.entries.elementAt(
                            index,
                          );
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScoreBadge(score: entry.value, size: 44),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                entry.key,
                                style: AppTypography.caption(colors),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}