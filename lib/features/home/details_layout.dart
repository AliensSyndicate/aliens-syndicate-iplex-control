import 'package:flutter/material.dart';

import '../../core/design_system/components.dart';
import '../../core/domain/models.dart';
import 'home_widgets.dart';

/// Shared look of the title and person pages: black page, fixed full-bleed
/// cover fading into the page, cover darkening while the content scrolls
/// over it, white back icon on the left and optional actions on the right.
class DetailsLayout extends StatefulWidget {
  const DetailsLayout({
    super.key,
    required this.height,
    required this.cover,
    required this.children,
    this.actions,
    this.coverFraction = 0.75,
    this.contentStart = 0.55,
  });

  /// Where the scrolling content starts, as a fraction of [height].
  final double contentStart;

  /// Page height (the cover and the content start are fractions of it).
  final double height;
  final Widget cover;
  final List<Widget> children;
  final Widget? actions;
  final double coverFraction;

  @override
  State<DetailsLayout> createState() => _DetailsLayoutState();
}

class _DetailsLayoutState extends State<DetailsLayout> {
  final scroll = ScrollController();

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  /// 0 at the top, black once the content scrolled [distance] (or reached
  /// the end of a shorter page).
  static double _dim(ScrollController scroll, double distance) {
    if (!scroll.hasClients || !scroll.position.hasContentDimensions) return 0;
    final max = scroll.position.maxScrollExtent;
    final span = max > 0 && max < distance ? max : distance;
    return (scroll.offset / span).clamp(0, 1).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final coverHeight = widget.height * widget.coverFraction;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Fixed artwork; only the content scrolls over it.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight,
          child: widget.cover,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight + 1,
          child: const DecoratedBox(
            key: Key('details-cover-fade'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: AppColors.coverFade,
                stops: [0, 0.18, 0.5, 0.7, 0.86, 1],
              ),
            ),
          ),
        ),
        // Scrolling up darkens the cover until it reaches the page black.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: coverHeight + 1,
          child: IgnorePointer(
            child: ListenableBuilder(
              listenable: scroll,
              builder: (context, _) => ColoredBox(
                key: const Key('details-cover-dim'),
                color: Colors.black.withValues(
                  alpha: _dim(scroll, widget.height * 0.5),
                ),
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          key: const Key('details-scroll'),
          controller: scroll,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            widget.height * widget.contentStart,
            AppSpacing.lg,
            AppSpacing.xl + padding.bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppDimensions.maxWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ),
        Positioned(
          top: padding.top + AppSpacing.sm,
          left: AppSpacing.lg,
          child: const DetailsBackButton(),
        ),
        if (widget.actions case final actions?)
          Positioned(
            top: padding.top + AppSpacing.sm,
            right: AppSpacing.sm,
            child: actions,
          ),
      ],
    );
  }
}

/// Icon only, white, no box (48 dp touch target).
class DetailsBackButton extends StatelessWidget {
  const DetailsBackButton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: context.l.back,
    excludeSemantics: true,
    child: InkResponse(
      key: const Key('details-back'),
      radius: AppDimensions.touch / 2,
      onTap: () => Navigator.of(context).maybePop(),
      child: const SizedBox.square(
        dimension: AppDimensions.touch,
        child: Center(
          child: AppIcon(AppIcons.left, color: Colors.white, size: 28),
        ),
      ),
    ),
  );
}

/// Full-bleed cover: the original TMDB poster, over the source artwork while
/// it loads (or when TMDB has no poster).
class DetailsCover extends StatelessWidget {
  const DetailsCover({
    super.key,
    required this.item,
    required this.url,
    required this.loading,
  });

  /// Source of the fallback art (initials when it has none).
  final Entry item;
  final String? url;

  /// TMDB still loading: nothing yet (the source art never flashes first).
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final fallback = Artwork(
      item: item,
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      background: Colors.black,
    );
    final cover = url;
    if (cover == null) {
      return loading ? const ColoredBox(color: Colors.black) : fallback;
    }
    // TMDB poster first; the source art only if it fails to load.
    return ColoredBox(
      color: Colors.black,
      child: Image.network(
        cover,
        key: const Key('details-cover'),
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        gaplessPlayback: true,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
          opacity: sync || frame != null ? 1 : 0,
          duration: AppMotion.pageEnter,
          child: child,
        ),
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }
}

/// Loading placeholder shaped like this page (cover, title, year line, play
/// button, text and cast portraits): flat blocks, no shadow or neumorphism,
/// gently pulsing. Shown until every piece of the page is known.
class DetailsSkeleton extends StatefulWidget {
  const DetailsSkeleton({super.key, required this.height, this.person = false});
  final double height;

  /// Person page shape: name, birthplace, dates, social icons, biography and
  /// filmography rows (no play button, no cast portraits).
  final bool person;
  @override
  State<DetailsSkeleton> createState() => _DetailsSkeletonState();
}

class _DetailsSkeletonState extends State<DetailsSkeleton> {
  /// Visible on the graphite and black backgrounds of this page.
  static const _block = AppColors.surfaceElevated;

  Widget _bar(double widthFactor, double height, {bool center = false}) =>
      FractionallySizedBox(
        alignment: center ? Alignment.center : Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: _block,
            borderRadius: BorderRadius.circular(AppRadii.xs),
          ),
        ),
      );

  Widget _block2(double width, double height, double radius) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: _block,
      borderRadius: BorderRadius.circular(radius),
    ),
  );

  List<Widget> _personBlocks() => [
    _bar(0.6, 26),
    const SizedBox(height: AppSpacing.md),
    _bar(0.35, 14),
    const SizedBox(height: AppSpacing.xs),
    _bar(0.3, 14),
    const SizedBox(height: AppSpacing.md),
    Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.md),
          _block2(28, 28, AppRadii.full),
        ],
      ],
    ),
    const SizedBox(height: AppSpacing.lg),
    for (final w in [1.0, 1.0, 1.0, 0.6]) ...[
      _bar(w, 12),
      const SizedBox(height: AppSpacing.xs),
    ],
    const SizedBox(height: AppSpacing.lg),
    _bar(0.4, 18),
    for (var i = 0; i < 2; i++) ...[
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          _block2(64, 96, AppRadii.card),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bar(0.7, 14),
                const SizedBox(height: AppSpacing.sm),
                _bar(0.45, 12),
              ],
            ),
          ),
        ],
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final cover = widget.height * 0.75;
    return Stack(
      key: const Key('details-skeleton'),
      fit: StackFit.expand,
      children: [
        AppSkeletonPulse(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Cover area fading into the page, like the loaded artwork.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: cover,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [_block, _block, Colors.black],
                      stops: [0, 0.5, 1],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: widget.height * 0.42,
                left: AppSpacing.lg,
                right: AppSpacing.lg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.person
                      ? _personBlocks()
                      : [
                          _bar(0.6, 26),
                          const SizedBox(height: AppSpacing.md),
                          _bar(0.45, 14),
                          const SizedBox(height: AppSpacing.sm),
                          _bar(0.3, 14),
                          const SizedBox(height: AppSpacing.lg),
                          // Action row: four round actions.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              for (var i = 0; i < 4; i++)
                                _block2(56, 56, AppRadii.full),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _bar(0.35, 12),
                          const SizedBox(height: AppSpacing.sm),
                          _bar(0.5, 12),
                          const SizedBox(height: AppSpacing.lg),
                          _bar(1, 12),
                          const SizedBox(height: AppSpacing.xs),
                          _bar(1, 12),
                          const SizedBox(height: AppSpacing.xs),
                          _bar(0.7, 12),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                if (i > 0) const SizedBox(width: AppSpacing.md),
                                Container(
                                  width: 96,
                                  height: 128,
                                  decoration: BoxDecoration(
                                    color: _block,
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.md,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
        Positioned(
          top: padding.top + AppSpacing.sm,
          left: AppSpacing.lg,
          child: const DetailsBackButton(),
        ),
      ],
    );
  }
}
