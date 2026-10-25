import 'package:flutter/material.dart';

/// Single source of truth for border radiuses in the Pair design system.
class AppRadius {
  AppRadius._();

  static const double sm = 12.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double card = 20.0;
  static const double input = 14.0;
  static const double full = 999.0;

  static const Radius radiusSm = Radius.circular(sm);
  static const Radius radiusMd = Radius.circular(md);
  static const Radius radiusLg = Radius.circular(lg);
  static const Radius radiusCard = Radius.circular(card);
  static const Radius radiusInput = Radius.circular(input);
  static const Radius radiusFull = Radius.circular(full);

  static const BorderRadius borderRadiusSm = BorderRadius.all(radiusSm);
  static const BorderRadius borderRadiusMd = BorderRadius.all(radiusMd);
  static const BorderRadius borderRadiusLg = BorderRadius.all(radiusLg);
  static const BorderRadius borderRadiusXl = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius borderRadiusCard = BorderRadius.all(radiusCard);
  static const BorderRadius borderRadiusInput = BorderRadius.all(radiusInput);
  static const BorderRadius borderRadiusFull = BorderRadius.all(radiusFull);
}
