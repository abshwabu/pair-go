import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_client.dart';
import '../../core/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../auth/auth_state.dart';
import '../pods/pod_state.dart';

class MatchConfirmedScreen extends ConsumerStatefulWidget {
  final String? podId;

  const MatchConfirmedScreen({
    super.key,
    this.podId,
  });

  @override
  ConsumerState<MatchConfirmedScreen> createState() =>
      _MatchConfirmedScreenState();
}

class _MatchConfirmedScreenState extends ConsumerState<MatchConfirmedScreen>
    with TickerProviderStateMixin {
  late AnimationController _celebrationController;
  late AnimationController _confettiController;
  late List<_ConfettiParticle> _particles;

  @override
  void initState() {
    super.initState();

    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..forward();

    final random = math.Random(42);
    _particles = List.generate(45, (index) {
      return _ConfettiParticle(
        x: random.nextDouble(),
        y: -0.1 - random.nextDouble() * 0.4,
        vx: (random.nextDouble() - 0.5) * 0.4,
        vy: 0.6 + random.nextDouble() * 0.8,
        size: 6.0 + random.nextDouble() * 6.0,
        rotation: random.nextDouble() * 2 * math.pi,
        rotationSpeed: (random.nextDouble() - 0.5) * 6,
        colorIndex: index % 5,
        isCircle: random.nextBool(),
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final apiClient = ref.read(apiClientProvider);
      ref.read(activePodDetailProvider.notifier).loadPod(
            apiClient: apiClient,
            podId: widget.podId,
          );
    });
  }

  @override
  void dispose() {
    _celebrationController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = context.tokens;
    final podState = ref.watch(activePodDetailProvider);
    final currentUser = ref.watch(currentUserProvider);
    final pod = podState.pod;

    final targetPodId = widget.podId ?? pod?.id;
    final partner = pod?.partner(currentUser?.id);
    final me = pod?.myMembership(currentUser?.id);

    final confettiColors = [
      colorScheme.primary,
      tokens.flame,
      colorScheme.tertiary,
      tokens.success,
      colorScheme.secondary,
    ];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xl,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.sm),

                      // Animated Central Badge
                      Center(
                        child: AnimatedBuilder(
                          animation: _celebrationController,
                          builder: (context, child) {
                            final scale = 1.0 +
                                (_celebrationController.value - 0.5) * 0.08;
                            return Transform.scale(
                              scale: scale,
                              child: Container(
                                width: 92,
                                height: 92,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colorScheme.primaryContainer,
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorScheme.primary
                                          .withValues(alpha: 0.28),
                                      blurRadius: 22,
                                      spreadRadius: 3,
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.celebration_rounded,
                                    size: 46,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // Title & Subtitle
                      Text(
                        "You're paired!",
                        style: AppTypography.headlineLarge.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onSurface,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Meet your accountability partner and crush your goals together.',
                        style: AppTypography.bodyMedium.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: AppSpacing.xl),

                      // Both Avatars and Both Goals
                      AppCard(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Current User Avatar
                                Column(
                                  children: [
                                    AppAvatar(
                                      size: AppAvatarSize.lg,
                                      imageUrl: currentUser?.avatarUrl,
                                      name: currentUser?.name ?? 'You',
                                      hasRing: true,
                                      ringColor: colorScheme.primary,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      currentUser?.name ?? 'You',
                                      style: AppTypography.labelMedium.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),

                                // Connecting Flame Badge
                                Container(
                                  padding: const EdgeInsets.all(AppSpacing.sm),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: tokens.flameBackground,
                                    border: Border.all(
                                      color: tokens.flame.withValues(alpha: 0.4),
                                      width: 1.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.local_fire_department_rounded,
                                    size: 26,
                                    color: tokens.flame,
                                  ),
                                ),

                                // Partner Avatar
                                Column(
                                  children: [
                                    AppAvatar(
                                      size: AppAvatarSize.lg,
                                      imageUrl: partner?.user.avatarUrl,
                                      name: partner?.user.name ?? 'Partner',
                                      hasRing: true,
                                      ringColor: tokens.flame,
                                    ),
                                    const SizedBox(height: AppSpacing.xs),
                                    Text(
                                      partner?.user.name ?? 'Partner',
                                      style: AppTypography.labelMedium.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),

                            const SizedBox(height: AppSpacing.lg),
                            const Divider(),
                            const SizedBox(height: AppSpacing.md),

                            // Goals comparison
                            if (me?.goal != null || partner?.goal != null)
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'YOUR GOAL',
                                          style: AppTypography.labelSmall
                                              .copyWith(
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          me?.goal.title ?? 'Your goal',
                                          style: AppTypography.bodySmall
                                              .copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    height: 36,
                                    width: 1,
                                    color: theme.dividerColor,
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          'PARTNER GOAL',
                                          style: AppTypography.labelSmall
                                              .copyWith(
                                            color: tokens.flame,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          partner?.goal.title ?? 'Partner goal',
                                          style: AppTypography.bodySmall
                                              .copyWith(
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurface,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpacing.xxl),

                      // Single Button: "Go to your pod"
                      AppButton.primary(
                        label: 'Go to your pod',
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          context.go(AppRoutes.podHomePath, extra: targetPodId);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Confetti Particle Animation Overlay
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _confettiController,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _ConfettiPainter(
                    progress: _confettiController.value,
                    particles: _particles,
                    colors: confettiColors,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfettiParticle {
  final double x;
  final double y;
  final double vx;
  final double vy;
  final double size;
  final double rotation;
  final double rotationSpeed;
  final int colorIndex;
  final bool isCircle;

  const _ConfettiParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.rotation,
    required this.rotationSpeed,
    required this.colorIndex,
    required this.isCircle,
  });
}

class _ConfettiPainter extends CustomPainter {
  final double progress;
  final List<_ConfettiParticle> particles;
  final List<Color> colors;

  _ConfettiPainter({
    required this.progress,
    required this.particles,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0 || progress >= 1.0) return;

    final alpha = ((1.0 - progress) * 1.5).clamp(0.0, 1.0);
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final currentX = (p.x + p.vx * progress) * size.width;
      final currentY = (p.y + p.vy * progress) * size.height;

      if (currentY < 0 || currentY > size.height) continue;

      final color = colors[p.colorIndex % colors.length];
      paint.color = color.withValues(alpha: alpha);

      canvas.save();
      canvas.translate(currentX, currentY);
      canvas.rotate(p.rotation + p.rotationSpeed * progress);

      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, p.size / 2, paint);
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: p.size,
            height: p.size * 0.6,
          ),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
