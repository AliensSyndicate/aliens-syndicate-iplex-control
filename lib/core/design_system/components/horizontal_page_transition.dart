import 'package:flutter/material.dart';

import '../tokens.dart';

/// Shared by secondary go_router pages and routes pushed by Navigator.
/// Main-menu branch pages deliberately do not use this transition.
class HorizontalPageTransition extends StatefulWidget {
  const HorizontalPageTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
    required this.curve,
    required this.reverseCurve,
  });

  final Animation<double> animation, secondaryAnimation;
  final Curve curve, reverseCurve;
  final Widget child;

  @override
  State<HorizontalPageTransition> createState() =>
      _HorizontalPageTransitionState();
}

class _HorizontalPageTransitionState extends State<HorizontalPageTransition> {
  late CurvedAnimation _primary, _secondary;

  void _createAnimations() {
    _primary = CurvedAnimation(
      parent: widget.animation,
      curve: widget.curve,
      reverseCurve: widget.reverseCurve,
    );
    _secondary = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: widget.curve,
      reverseCurve: widget.reverseCurve,
    );
  }

  @override
  void initState() {
    super.initState();
    _createAnimations();
  }

  @override
  void didUpdateWidget(HorizontalPageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation ||
        oldWidget.secondaryAnimation != widget.secondaryAnimation ||
        oldWidget.curve != widget.curve ||
        oldWidget.reverseCurve != widget.reverseCurve) {
      _primary.dispose();
      _secondary.dispose();
      _createAnimations();
    }
  }

  @override
  void dispose() {
    _primary.dispose();
    _secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(_primary),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.25, 0),
        ).animate(_secondary),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.backgroundPrimary,
            boxShadow: [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 16,
                spreadRadius: 2,
                offset: Offset(-4, 0),
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              IgnorePointer(
                child: FadeTransition(
                  opacity: Tween<double>(
                    begin: 0.0,
                    end: 0.25,
                  ).animate(_secondary),
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Applied to main-menu root pages to displace left during child navigation,
/// without adding horizontal entrance transitions when switching tabs.
class SecondaryDisplacementTransition extends StatefulWidget {
  const SecondaryDisplacementTransition({
    super.key,
    required this.secondaryAnimation,
    required this.child,
    required this.curve,
    required this.reverseCurve,
  });

  final Animation<double> secondaryAnimation;
  final Curve curve, reverseCurve;
  final Widget child;

  @override
  State<SecondaryDisplacementTransition> createState() =>
      _SecondaryDisplacementTransitionState();
}

class _SecondaryDisplacementTransitionState
    extends State<SecondaryDisplacementTransition> {
  late CurvedAnimation _secondary;

  void _createAnimation() {
    _secondary = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: widget.curve,
      reverseCurve: widget.reverseCurve,
    );
  }

  @override
  void initState() {
    super.initState();
    _createAnimation();
  }

  @override
  void didUpdateWidget(SecondaryDisplacementTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation ||
        oldWidget.curve != widget.curve ||
        oldWidget.reverseCurve != widget.reverseCurve) {
      _secondary.dispose();
      _createAnimation();
    }
  }

  @override
  void dispose() {
    _secondary.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.25, 0),
      ).animate(_secondary),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          widget.child,
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 0.25).animate(_secondary),
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }
}
