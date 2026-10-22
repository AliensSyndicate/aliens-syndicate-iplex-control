import 'package:flutter/material.dart';

import '../graphite_surface.dart';
import '../tokens.dart';
import 'app_network_image.dart';

/// Only https photos are drawn; anything else shows the default avatar.
String? avatarPhotoOrNull(String? url) =>
    url != null && url.startsWith('https://') ? url : null;

/// Face of an avatar: the provider photo when there is one, otherwise the default
/// iPlex avatar (initial of the name, `i` without a name). Not tied to a surface,
/// so a circular button can use it as its content.
class AppAvatarFace extends StatelessWidget {
  const AppAvatarFace({
    super.key,
    required this.name,
    this.photoUrl,
    required this.size,
  });
  final String name;
  final String? photoUrl;
  final double size;

  Widget _initial(BuildContext context) => Center(
    child: Text(
      name.isEmpty ? 'i' : name.characters.first.toUpperCase(),
      style: size < AppDimensions.avatar
          ? Theme.of(context).textTheme.titleMedium
          : Theme.of(context).textTheme.headlineMedium,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final url = avatarPhotoOrNull(photoUrl);
    return SizedBox.square(
      dimension: size,
      child: url == null
          ? _initial(context)
          : ClipOval(
              child: Image(
                image: CachedNetworkImage(
                  url,
                  decodeWidth: (size * MediaQuery.devicePixelRatioOf(context))
                      .round(),
                ),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                excludeFromSemantics: true,
                errorBuilder: (context, error, stack) => _initial(context),
              ),
            ),
    );
  }
}

class AppAvatar extends StatelessWidget {
  const AppAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = AppDimensions.avatar,
  });
  final String name;
  final String? photoUrl;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: GraphiteSurface(
      circle: true,
      finish: GraphiteFinish.button,
      padding: avatarPhotoOrNull(photoUrl) == null
          ? EdgeInsets.zero
          : const EdgeInsets.all(AppSpacing.xs),
      child: AppAvatarFace(name: name, photoUrl: photoUrl, size: size),
    ),
  );
}
