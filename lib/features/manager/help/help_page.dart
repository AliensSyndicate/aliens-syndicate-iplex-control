import 'package:flutter/material.dart';

import '../../../core/design_system/components.dart';
import 'help_content.dart';

/// Ajuda e suporte: frequently asked questions grouped by topic and a filter
/// over questions and answers.
class HelpPage extends StatefulWidget {
  const HelpPage({super.key});
  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  final _filter = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final terms = _normalize(_query).split(' ').where((t) => t.isNotEmpty);
    bool matches(HelpItem item) {
      final text = _normalize('${item.question} ${item.answer}');
      return terms.every(text.contains);
    }

    final topics = [
      for (final topic in helpTopics(
        Localizations.localeOf(context).languageCode,
      ))
        (topic.title, topic.items.where(matches).toList()),
    ].where((t) => t.$2.isNotEmpty).toList();

    return Scaffold(
      body: PageTemplate(
        title: l.help,
        showBack: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            NeumorphicSearchField(
              key: const Key('help-filter'),
              controller: _filter,
              hintText: l.helpSearchHint,
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: AppSpacing.md),
            if (topics.isEmpty)
              EmptyState(
                title: l.helpNoResultsTitle,
                body: l.helpNoResultsBody,
                icon: AppIcons.search,
              )
            else
              for (final (title, items) in topics) ...[
                SectionHeader(title),
                // Keyed by question so an open item stays open while filtering.
                for (final item in items)
                  _HelpAccordion(key: ValueKey(item.question), item: item),
              ],
          ],
        ),
      ),
    );
  }
}

/// Lowercase without accents, so "familia" finds "Família".
String _normalize(String value) => value
    .toLowerCase()
    .replaceAll(RegExp('[áàâãä]'), 'a')
    .replaceAll(RegExp('[éèêë]'), 'e')
    .replaceAll(RegExp('[íìîï]'), 'i')
    .replaceAll(RegExp('[óòôõö]'), 'o')
    .replaceAll(RegExp('[úùûü]'), 'u')
    .replaceAll('ç', 'c')
    .replaceAll('ñ', 'n')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// One question: the list card look; tapping opens the answer below it.
class _HelpAccordion extends StatefulWidget {
  const _HelpAccordion({super.key, required this.item});
  final HelpItem item;
  @override
  State<_HelpAccordion> createState() => _HelpAccordionState();
}

class _HelpAccordionState extends State<_HelpAccordion> {
  bool open = false;

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.duration(context, AppMotion.pageEnter);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Semantics(
        button: true,
        expanded: open,
        child: Material(
          color: AppColors.surfaceDefault,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.card),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => open = !open),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.item.question,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: duration,
                        curve: AppMotion.pageCurve,
                        child: const AppIcon(
                          AppIcons.down,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  AnimatedSize(
                    duration: duration,
                    curve: AppMotion.pageCurve,
                    alignment: Alignment.topCenter,
                    child: open
                        ? Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: Text(
                              widget.item.answer,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                height: 1.5,
                              ),
                            ),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
