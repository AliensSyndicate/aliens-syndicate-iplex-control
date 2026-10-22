import 'package:flutter/material.dart';

import '../core/design_system/tokens.dart';

/// Keeps the launch splash (same image and colour as the native one) on screen
/// for a minimum time after the first Flutter frame, then fades to the app.
class SplashGate extends StatefulWidget {
  const SplashGate({
    super.key,
    required this.child,
    this.minimum = const Duration(milliseconds: 1500),
  });
  final Widget child;
  final Duration minimum;

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  static const _color = AppColors.backgroundDeep;
  static const _logo = AssetImage('assets/images/launcher.png');
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // Count the minimum from the first painted frame: debug/cold starts can
    // spend longer than [minimum] before anything reaches the screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await precacheImage(_logo, context);
      await Future<void>.delayed(widget.minimum);
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          ignoring: _done,
          child: AnimatedOpacity(
            opacity: _done ? 0 : 1,
            duration: const Duration(milliseconds: 300),
            child: const ColoredBox(
              color: _color,
              child: Center(child: Image(image: _logo, width: 160)),
            ),
          ),
        ),
      ],
    ),
  );
}
