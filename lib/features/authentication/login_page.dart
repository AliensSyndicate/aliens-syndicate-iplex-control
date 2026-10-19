import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/data/providers.dart';
import '../../core/design_system/components.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  String? busy;
  Future<void> login(String provider) async {
    setState(() => busy = provider);
    try {
      await ref.read(repositoryProvider).signIn(provider);
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      child: Column(
                        children: [
                          // Linha de cima: expansível, com coluna contendo logo e texto (sem título)
                          Expanded(
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.card,
                                    ),
                                    child: Image.asset(
                                      'assets/images/launcher.png',
                                      height: 164,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                  Text(
                                    l.loginSubtitle,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: AppColors.textSecondary,
                                      height: 1.4,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Linha de baixo: altura fit, com botões e links alinhados ao bottom
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              AppButton(
                                label: l.google,
                                icon: AppIcons.google,
                                busy: busy == 'google',
                                onPressed: busy == null
                                    ? () => login('google')
                                    : null,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AppButton(
                                label: l.apple,
                                icon: AppIcons.apple,
                                busy: busy == 'apple',
                                onPressed: busy == null
                                    ? () => login('apple')
                                    : null,
                              ),
                              if (!ref
                                  .watch(repositoryProvider)
                                  .configured) ...[
                                const SizedBox(height: AppSpacing.md),
                                Text(
                                  l.configurationRequired,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: AppSpacing.xl),
                              Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  TextButton(
                                    onPressed: () =>
                                        context.push('/legal/terms'),
                                    child: Text(
                                      l.terms,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            AppColors.textSecondary,
                                      ),
                                    ),
                                  ),

                                  TextButton(
                                    onPressed: () =>
                                        context.push('/legal/privacy'),
                                    child: Text(
                                      l.privacy,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
