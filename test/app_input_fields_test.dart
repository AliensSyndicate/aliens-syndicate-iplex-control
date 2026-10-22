import 'package:aliens_syndicate_iplex_control/core/design_system/components.dart';
import 'package:aliens_syndicate_iplex_control/core/design_system/components/app_input_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(24), child: child),
  ),
);

Finder control() => find.descendant(
  of: find.byType(AppInputFrame),
  matching: find.byWidgetPredicate((w) => w is SizedBox && w.height == 56),
);

void main() {
  testWidgets(
    'fixed label and 56px surface persist through focus and validation',
    (tester) async {
      final controller = TextEditingController();
      final focus = FocusNode();
      final form = GlobalKey<FormState>();
      await tester.pumpWidget(
        host(
          Form(
            key: form,
            child: AppTextField(
              label: 'Nome',
              controller: controller,
              focusNode: focus,
              validator: (value) =>
                  value!.isEmpty ? 'Preencha o nome para continuar.' : null,
            ),
          ),
        ),
      );
      final labelPosition = tester.getTopLeft(find.text('Nome'));
      expect(tester.getSize(control()).height, 56);
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Preencha o nome para continuar.'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Preencha o nome para continuar.')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(control()).dy),
      );
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Nome')).style!.color, Colors.white);
      final container = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(AppInputFrame),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        ((container.decoration! as BoxDecoration).border! as Border).top.color,
        Colors.white,
      );
      await tester.enterText(find.byType(TextFormField), 'Minha lista');
      await tester.pumpAndSettle();
      expect(find.text('Preencha o nome para continuar.'), findsNothing);
      expect(tester.getTopLeft(find.text('Nome')), labelPosition);
      expect(tester.getSize(control()).height, 56);
      form.currentState!.reset();
      await tester.pumpAndSettle();
      expect(find.text('Preencha o nome para continuar.'), findsNothing);
      controller.clear();
      expect(controller.text, isEmpty);
      expect(
        tester.state<FormFieldState<String>>(find.byType(TextFormField)).value,
        isEmpty,
      );
      expect(form.currentState!.validate(), isFalse);
      await tester.pumpAndSettle();
      expect(find.text('Preencha o nome para continuar.'), findsOneWidget);
      form.currentState!.reset();
      focus.unfocus();
      await tester.pumpAndSettle();
      expect(find.text('Preencha o nome para continuar.'), findsNothing);
      expect(
        tester.widget<Text>(find.text('Nome')).style!.color,
        AppColors.textSecondary,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      // Externally supplied nodes remain owned by the caller.
      focus.addListener(() {});
      focus.dispose();
      controller.dispose();
    },
  );

  testWidgets(
    'password, search and dropdown use the same fixed control height',
    (tester) async {
      final secret = TextEditingController();
      final search = TextEditingController();
      final focus = FocusNode();
      await tester.pumpWidget(
        host(
          Column(
            children: [
              AppTextField(label: 'Senha', controller: secret, secret: true),
              AppTextField(
                label: 'Buscar',
                controller: search,
                prefixIcon: const Icon(Icons.search),
              ),
              AppDropdownField<String>(
                label: 'Idioma',
                initialValue: 'pt',
                focusNode: focus,
                items: const [
                  DropdownMenuItem(value: 'pt', child: Text('Português')),
                ],
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );
      expect(control(), findsNWidgets(3));
      for (final element in control().evaluate()) {
        expect(
          tester.getSize(find.byElementPredicate((e) => e == element)).height,
          56,
        );
      }
      focus.requestFocus();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.text('Idioma')).style!.color,
        Colors.white,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      focus.dispose();
      secret.dispose();
      search.dispose();
    },
  );
}
