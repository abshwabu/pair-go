import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_radii.dart';
import '../theme/app_spacing.dart';
import '../theme/theme_mode_provider.dart';

/// Reusable theme selector offering System, Light, and Dark mode choices.
class ThemeModeSelector extends ConsumerWidget {
  final bool isCompact;

  const ThemeModeSelector({
    super.key,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentMode = ref.watch(themeModeProvider);
    final theme = Theme.of(context);

    if (isCompact) {
      return Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: AppRadius.borderRadiusFull,
        ),
        padding: const EdgeInsets.all(AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _CompactOption(
              icon: Icons.brightness_auto,
              isSelected: currentMode == ThemeMode.system,
              tooltip: 'System',
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system),
            ),
            _CompactOption(
              icon: Icons.light_mode,
              isSelected: currentMode == ThemeMode.light,
              tooltip: 'Light',
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light),
            ),
            _CompactOption(
              icon: Icons.dark_mode,
              isSelected: currentMode == ThemeMode.dark,
              tooltip: 'Dark',
              onTap: () => ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.dark),
            ),
          ],
        ),
      );
    }

    return SegmentedButton<ThemeMode>(
      segments: const [
        ButtonSegment<ThemeMode>(
          value: ThemeMode.system,
          icon: Icon(Icons.brightness_auto, size: 18),
          label: Text('System'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.light,
          icon: Icon(Icons.light_mode, size: 18),
          label: Text('Light'),
        ),
        ButtonSegment<ThemeMode>(
          value: ThemeMode.dark,
          icon: Icon(Icons.dark_mode, size: 18),
          label: Text('Dark'),
        ),
      ],
      selected: {currentMode},
      onSelectionChanged: (newSelection) {
        if (newSelection.isNotEmpty) {
          ref
              .read(themeModeProvider.notifier)
              .setThemeMode(newSelection.first);
        }
      },
      showSelectedIcon: false,
    );
  }
}

class _CompactOption extends StatelessWidget {
  final IconData icon;
  final bool isSelected;
  final String tooltip;
  final VoidCallback onTap;

  const _CompactOption({
    required this.icon,
    required this.isSelected,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.full),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xs + 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isSelected
                ? theme.colorScheme.primary
                : Colors.transparent,
          ),
          child: Icon(
            icon,
            size: 18,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
