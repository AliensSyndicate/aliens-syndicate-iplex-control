import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/design_system/components.dart';
import 'about_content.dart';

/// Sobre: what iPlex is, who makes it, the installed version and how it
/// stores data and runs.
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final Future<PackageInfo?> _packageInfo = PackageInfo.fromPlatform()
      .then<PackageInfo?>((info) => info)
      .catchError((Object _) => null);

  @override
  Widget build(BuildContext context) {
    final content = aboutContent(Localizations.localeOf(context).languageCode);
    Widget section(String title, String body) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Text(
          body,
          style: const TextStyle(color: AppColors.textSecondary, height: 1.5),
        ),
      ],
    );

    return Scaffold(
      body: PageTemplate(
        title: context.l.about,
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const IplexWordmark(),
            const SizedBox(height: AppSpacing.sm),
            Text(
              content.tagline,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                height: 1.5,
              ),
            ),
            for (final (i, (title, body)) in content.sections.indexed) ...[
              section(title, body),
              if (i == 1)
                FutureBuilder<PackageInfo?>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    return section(
                      content.versionTitle,
                      snapshot.connectionState != ConnectionState.done
                          ? content.loading
                          : info == null
                          ? '—'
                          : '${info.version} (${content.build} ${info.buildNumber})',
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
