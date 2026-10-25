import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/widgets.dart';

/// Debug-only design gallery showcasing design tokens and widget kit components in light & dark modes.
class DesignGalleryScreen extends StatefulWidget {
  const DesignGalleryScreen({super.key});

  @override
  State<DesignGalleryScreen> createState() => _DesignGalleryScreenState();
}

class _DesignGalleryScreenState extends State<DesignGalleryScreen> {
  bool _isLoadingButtons = false;
  final _textController = TextEditingController(text: 'Editable text');

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;

    return AppScaffold(
      appBar: AppBar(
        title: const Text('Design System Gallery'),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: AppSpacing.md),
            child: ThemeModeSelector(isCompact: true),
          ),
        ],
      ),
      isScrollable: true,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Theme Switcher Section
          const SectionHeader(title: 'Theme Mode'),
          const AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Switch between System, Light, and Dark:'),
                SizedBox(height: AppSpacing.md),
                ThemeModeSelector(),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Typography Section
          const SectionHeader(title: 'Typography (Plus Jakarta Sans)'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Display Large 32/700', style: theme.textTheme.displayLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('Headline Large 24/700', style: theme.textTheme.headlineLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('Title Large 20/600', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('Body Large 16/400 comfortable line height', style: theme.textTheme.bodyLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('Body Small 14/400 comfortable line height', style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xs),
                Text('Label Large 14/600', style: theme.textTheme.labelLarge),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Color Tokens Section
          const SectionHeader(title: 'Color Tokens'),
          AppCard(
            child: Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                _ColorSwatch(label: 'Primary', color: colorScheme.primary),
                _ColorSwatch(label: 'Flame/Accent', color: tokens.flame),
                _ColorSwatch(label: 'Surface', color: colorScheme.surface),
                _ColorSwatch(label: 'Surface Elev', color: tokens.surfaceElevated),
                _ColorSwatch(label: 'Success', color: tokens.success),
                _ColorSwatch(label: 'Warning', color: tokens.warning),
                _ColorSwatch(label: 'Error', color: colorScheme.error),
                _ColorSwatch(label: 'Outline', color: tokens.outlineSubtle),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // AppButton Section
          SectionHeader(
            title: 'Buttons (AppButton)',
            trailing: Switch(
              value: _isLoadingButtons,
              onChanged: (val) => setState(() => _isLoadingButtons = val),
            ),
          ),
          AppCard(
            child: Column(
              children: [
                AppButton.primary(
                  label: 'Primary Button',
                  leadingIcon: Icons.bolt_rounded,
                  isLoading: _isLoadingButtons,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.secondary(
                  label: 'Secondary / Outlined Button',
                  leadingIcon: Icons.tune_rounded,
                  isLoading: _isLoadingButtons,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.tonal(
                  label: 'Tonal Button',
                  leadingIcon: Icons.layers_rounded,
                  isLoading: _isLoadingButtons,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.text(
                  label: 'Text Button',
                  leadingIcon: Icons.arrow_forward_rounded,
                  isLoading: _isLoadingButtons,
                  onPressed: () {},
                ),
                const SizedBox(height: AppSpacing.md),
                const AppButton.primary(
                  label: 'Disabled Button',
                  onPressed: null,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // AppTextField Section
          const SectionHeader(title: 'Input Fields (AppTextField)'),
          AppCard(
            child: Column(
              children: [
                AppTextField(
                  label: 'Standard Input',
                  hint: 'Enter your goal...',
                  controller: _textController,
                  prefixIcon: Icons.flag_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                const AppTextField(
                  label: 'Password Input',
                  hint: 'Enter your password',
                  isPassword: true,
                  prefixIcon: Icons.lock_outline_rounded,
                  helper: 'Minimum 8 characters',
                ),
                const SizedBox(height: AppSpacing.md),
                const AppTextField(
                  label: 'Error State Input',
                  hint: 'Invalid entry',
                  error: 'This goal category is required.',
                  prefixIcon: Icons.error_outline_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Avatars Section
          const SectionHeader(title: 'Avatars (AppAvatar)'),
          AppCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const Column(
                  children: [
                    AppAvatar(size: AppAvatarSize.sm, name: 'Alex Johnson'),
                    SizedBox(height: AppSpacing.xs),
                    Text('sm (32)'),
                  ],
                ),
                const Column(
                  children: [
                    AppAvatar(size: AppAvatarSize.md, name: 'Sarah Connor'),
                    SizedBox(height: AppSpacing.xs),
                    Text('md (44)'),
                  ],
                ),
                const Column(
                  children: [
                    AppAvatar(size: AppAvatarSize.lg, name: 'David Lee', hasRing: true),
                    SizedBox(height: AppSpacing.xs),
                    Text('lg + ring (56)'),
                  ],
                ),
                const Column(
                  children: [
                    AppAvatar(size: AppAvatarSize.xl, name: 'Emma Watson', hasRing: true),
                    SizedBox(height: AppSpacing.xs),
                    Text('xl + ring (72)'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Status Chips Section
          const SectionHeader(title: 'Status Chips (StatusChip)'),
          const AppCard(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                StatusChip.success(label: 'Goal Met', icon: Icons.check_circle_outline),
                StatusChip.warning(label: 'Pending', icon: Icons.schedule_rounded),
                StatusChip.error(label: 'Broken Streak', icon: Icons.warning_amber_rounded),
                StatusChip.streak(label: '7 Day Streak'),
                StatusChip(label: 'Info Chip', icon: Icons.info_outline),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // EmptyState Section
          const SectionHeader(title: 'Empty State (EmptyState)'),
          AppCard(
            padding: EdgeInsets.zero,
            child: EmptyState(
              icon: Icons.checklist_rounded,
              title: 'No Active Tasks',
              message: 'You are all caught up for today. Add a new goal to get started.',
              actionLabel: 'Add Task',
              onAction: () {},
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Shimmer Placeholders Section
          const SectionHeader(title: 'Shimmers & Skeletons (AppShimmer)'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppShimmer.listRow(),
                const Divider(),
                AppShimmer.listRow(),
                const SizedBox(height: AppSpacing.md),
                AppShimmer.card(height: 80),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Dialogs & SnackBars Helpers Section
          const SectionHeader(title: 'Dialog & Sheet Helpers'),
          AppCard(
            child: Column(
              children: [
                AppButton.secondary(
                  label: 'Show App Bottom Sheet',
                  onPressed: () {
                    showAppBottomSheet(
                      context: context,
                      builder: (sheetCtx) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Design System Bottom Sheet',
                                style: Theme.of(sheetCtx).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              const Text('Consistent top radius of 24 and drag handle.'),
                              const SizedBox(height: AppSpacing.xl),
                              AppButton.primary(
                                label: 'Close',
                                onPressed: () => Navigator.of(sheetCtx).pop(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.secondary(
                  label: 'Show App Dialog',
                  onPressed: () {
                    showAppDialog(
                      context: context,
                      builder: (dlgCtx) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.palette_rounded, size: 40),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Design System Dialog',
                            style: Theme.of(dlgCtx).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          const Text('Radius 24 with elevated padding.'),
                          const SizedBox(height: AppSpacing.xl),
                          AppButton.primary(
                            label: 'Dismiss',
                            onPressed: () => Navigator.of(dlgCtx).pop(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                AppButton.secondary(
                  label: 'Show App SnackBar',
                  onPressed: () {
                    showAppSnackBar(
                      context: context,
                      message: 'Design system notification message.',
                      actionLabel: 'Undo',
                      onAction: () {},
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  final String label;
  final Color color;

  const _ColorSwatch({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color,
            borderRadius: AppRadius.borderRadiusSm,
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.labelSmall,
        ),
      ],
    );
  }
}
