import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

enum AppPageTransition {
  sharedAxisHorizontal,
  sharedAxisVertical,
  sharedAxisScaled,
  fadeThrough,
}

/// A go_router [CustomTransitionPage] helper that applies animated page transitions
/// (SharedAxis or FadeThrough) from the animations package, while respecting
/// reduced motion preferences.
class AppPage<T> extends CustomTransitionPage<T> {
  AppPage({
    required super.child,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
    AppPageTransition transition = AppPageTransition.sharedAxisHorizontal,
    Duration duration = const Duration(milliseconds: 300),
  }) : super(
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
              return child;
            }

            switch (transition) {
              case AppPageTransition.sharedAxisHorizontal:
                return SharedAxisTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.horizontal,
                  child: child,
                );
              case AppPageTransition.sharedAxisVertical:
                return SharedAxisTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.vertical,
                  child: child,
                );
              case AppPageTransition.sharedAxisScaled:
                return SharedAxisTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  transitionType: SharedAxisTransitionType.scaled,
                  child: child,
                );
              case AppPageTransition.fadeThrough:
                return FadeThroughTransition(
                  animation: animation,
                  secondaryAnimation: secondaryAnimation,
                  child: child,
                );
            }
          },
        );
}
