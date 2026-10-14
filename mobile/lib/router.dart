import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const BlankHomeScreen(),
    ),
  ],
);

class BlankHomeScreen extends StatelessWidget {
  const BlankHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: SafeArea(
        child: SizedBox.expand(),
      ),
    );
  }
}
