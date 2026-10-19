import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../tokens.dart';

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.size = AppDimensions.avatar,
  });
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: GraphiteSurface(
      circle: true,
      finish: GraphiteFinish.button,
      child: Center(
        child: Text(
          name.isEmpty ? 'i' : name.characters.first.toUpperCase(),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    ),
  );
}
