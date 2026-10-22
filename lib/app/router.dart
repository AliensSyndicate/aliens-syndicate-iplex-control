import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/data/providers.dart';
import '../core/design_system/components.dart';
import '../features/authentication/login_page.dart';
import '../features/manager/account_page.dart';
import '../features/home/content_details_page.dart';
import '../features/home/home_data.dart';
import '../features/home/home_page.dart';
import '../features/home/home_section_page.dart';
import '../features/home/person_page.dart';
import '../features/home/search_page.dart';
import '../core/domain/models.dart';
import '../features/manager/detail_page.dart';
import '../features/manager/profile_link_redeem_page.dart';
import '../features/manager/profile_manage_page.dart';
import '../features/devices/presentation/pages/device_list_page.dart';
import '../features/manager/information_page.dart';
import '../features/manager/invite_page.dart';
import '../features/manager/name_form.dart';
import '../features/manager/parental_control_page.dart';
import '../features/manager/profile_data_page.dart';
import '../features/manager/scan_page.dart';
import '../features/manager/settings_page.dart';
import '../features/manager/iptv_page.dart';
import '../features/manager/iptv_source_form.dart';
import '../features/manager/list_iptv_page.dart';
import '../features/manager/subscription_page.dart';
import '../features/manager/users_page.dart';
import '../features/legal/domain/enums/legal_document_type.dart';
import '../features/legal/presentation/pages/legal_webview_page.dart';
import '../features/iptv/presentation/controllers/iptv_notification_controller.dart';
import '../features/devices/presentation/pages/device_add_page.dart';
import '../features/devices/presentation/pages/device_confirm_pairing_page.dart';
import '../features/devices/presentation/pages/device_detail_page.dart';
import '../features/devices/presentation/pages/device_manual_code_page.dart';
import '../features/devices/presentation/pages/device_pairing_success_page.dart';
import '../features/devices/presentation/pages/device_qr_scanner_page.dart';
import 'main_shell.dart';
import 'route_access_page.dart';
import 'router_refresh.dart';
import 'session_loading_page.dart';

// Defaults to Home; explicit platform deep links still take precedence in go_router.
final initialRouteProvider = Provider<String>((ref) => '/home');

String? _requestedDestination(Uri location) {
  final String? raw = ['/login', '/loading'].contains(location.path)
      ? location.queryParameters['from']
      : location.toString();
  if (raw == null || !raw.startsWith('/') || raw.startsWith('//')) return null;
  final destination = Uri.tryParse(raw);
  if (destination == null ||
      destination.hasScheme ||
      destination.hasAuthority ||
      destination.path.isEmpty ||
      ['/login', '/loading', '/access'].contains(destination.path) ||
      destination.path.startsWith('/legal')) {
    return null;
  }
  return destination.toString();
}

String _gateLocation(String path, String? destination) => Uri(
  path: path,
  queryParameters: destination == null || destination == '/home'
      ? null
      : {'from': destination},
).toString();
bool _requiresFamily(String path) => path.startsWith('/users/');
bool _requiresAdmin(String path) =>
    !path.startsWith('/iptv/') &&
    (path.endsWith('/edit') ||
        path.endsWith('/add') ||
        path == '/users/invite');

Page<dynamic> _appPage({
  required LocalKey key,
  required Widget child,
  String? name,
}) => CustomTransitionPage<void>(
  key: key,
  name: name,
  child: child,
  transitionDuration: AppMotion.pageEnter,
  reverseTransitionDuration: AppMotion.pageExit,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return HorizontalPageTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      curve: AppMotion.pageCurve,
      reverseCurve: AppMotion.exitCurve,
      child: child,
    );
  },
);

Page<dynamic> _rootPage({required LocalKey key, required Widget child}) =>
    CustomTransitionPage<void>(
      key: key,
      child: child,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return SecondaryDisplacementTransition(
          secondaryAnimation: secondaryAnimation,
          curve: AppMotion.pageCurve,
          reverseCurve: AppMotion.exitCurve,
          child: child,
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = RouterRefresh();
  ref.onDispose(refresh.dispose);
  String? lastAuthenticatedUid = ref.read(authProvider).asData?.value;
  var justSignedOut = false;
  ref.listen(authProvider, (previous, next) {
    if (!next.isLoading && !next.hasError) {
      final uid = next.asData?.value;
      if (lastAuthenticatedUid != null && uid == null) justSignedOut = true;
      lastAuthenticatedUid = uid;
    }
    refresh.refresh();
  });
  ref.listen(accountProvider, (_, _) => refresh.refresh());
  ref.listen(familyProvider, (_, _) => refresh.refresh());
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    observers: [iptvNotificationRouteObserver],
    initialLocation: ref.read(initialRouteProvider),
    refreshListenable: refresh,
    redirect: (context, state) {
      final path = state.uri.path;
      if (path.startsWith('/legal')) {
        return null;
      }
      final auth = ref.read(authProvider);
      final account = ref.read(accountProvider);
      final family = ref.read(familyProvider);
      final destination = _requestedDestination(state.uri);
      final gate = _gateLocation('/loading', destination);
      if (auth.isLoading || auth.hasError) {
        return path == '/loading' ? null : gate;
      }
      final uid = auth.asData?.value;
      if (uid == null) {
        // Logging out starts a fresh login at Home. A later explicit deep link
        // is a new navigation request and may retain its own destination.
        if (justSignedOut) {
          // Multiple provider refreshes can evaluate the old private location
          // before the first redirect completes. Keep the logout destination
          // stable until the clean Login location has actually been reached.
          if (path != '/login' ||
              state.uri.queryParameters.containsKey('from')) {
            return '/login';
          }
          justSignedOut = false;
          return null;
        }
        return path == '/login' ? null : _gateLocation('/login', destination);
      }
      if (account.isLoading ||
          account.hasError ||
          account.asData?.value?.uid != uid) {
        return path == '/loading' ? null : gate;
      }
      final target = ['/login', '/loading'].contains(path)
          ? destination ?? '/home'
          : state.uri.toString();
      final targetPath = Uri.parse(target).path;
      if (targetPath.startsWith('/iptv/') &&
          (targetPath.endsWith('/add') || targetPath.endsWith('/edit'))) {
        final current = account.asData!.value!;
        if (current.iptvWorkspaceId == null &&
            current.familyId != null &&
            (family.isLoading || family.hasError)) {
          return path == '/loading' ? null : gate;
        }
        if (!ref.read(canManageIptvProvider)) {
          return '/access?reason=permission';
        }
      }
      // Family setup is optional navigation. It never gates the main shell.
      if (_requiresFamily(targetPath) &&
          account.asData!.value!.familyId == null) {
        return '/access?reason=family';
      }
      if (_requiresAdmin(targetPath)) {
        if (family.isLoading || family.hasError) {
          return path == '/loading' ? null : gate;
        }
        if (!ref.read(canManageResourcesProvider)) {
          return '/access?reason=permission';
        }
      }
      if (path == '/login' || path == '/loading' || path == '/') {
        return target == '/' ? '/home' : target;
      }
      return null;
    },
    errorBuilder: (c, s) => Scaffold(body: Center(child: Text(c.l.notFound))),
    routes: [
      GoRoute(path: '/', redirect: (c, s) => '/home'),
      GoRoute(
        path: '/access',
        pageBuilder: (c, s) => _appPage(
          key: s.pageKey,
          child: RouteAccessPage(
            familyRequired: s.uri.queryParameters['reason'] == 'family',
          ),
        ),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (c, s) =>
            _appPage(key: s.pageKey, child: const LoginPage()),
      ),
      GoRoute(
        path: '/loading',
        pageBuilder: (c, s) =>
            _appPage(key: s.pageKey, child: const SessionLoadingPage()),
      ),
      GoRoute(
        path: '/legal/terms',
        pageBuilder: (c, s) => _appPage(
          key: s.pageKey,
          child: const LegalWebViewPage(type: LegalDocumentType.termsOfUse),
        ),
      ),
      GoRoute(
        path: '/legal/privacy',
        pageBuilder: (c, s) => _appPage(
          key: s.pageKey,
          child: const LegalWebViewPage(type: LegalDocumentType.privacyPolicy),
        ),
      ),
      GoRoute(
        path: '/legal/:type',
        redirect: (c, s) {
          final type = s.pathParameters['type'];
          if (type == 'terms') return '/legal/terms';
          if (type == 'privacy') return '/legal/privacy';
          return null;
        },
      ),

      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const HomePage()),
                routes: [
                  // Full details pages (never a sheet). Catalog items travel
                  // as `extra`; editorial titles are addressed by TMDB id.
                  GoRoute(
                    path: 'title',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: ContentDetailsPage(item: s.extra as Entry?),
                    ),
                    routes: [
                      GoRoute(
                        path: ':kind/:tmdbId',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: ContentDetailsPage(
                            item: s.extra as Entry?,
                            kind: s.pathParameters['kind'],
                            tmdbId: int.tryParse(
                              s.pathParameters['tmdbId'] ?? '',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'section/:id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: HomeSectionPage(
                        section: HomeSection.values.firstWhere(
                          (v) => v.name == s.pathParameters['id'],
                          orElse: () => HomeSection.favorites,
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'person/:id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: PersonPage(
                        tmdbId: int.tryParse(s.pathParameters['id'] ?? '') ?? 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/users',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const UsersPage()),
                routes: [
                  GoRoute(
                    path: 'invite',
                    pageBuilder: (c, s) =>
                        _appPage(key: s.pageKey, child: const InvitePage()),
                  ),
                  GoRoute(
                    path: 'scan',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const ScanPage(device: false),
                    ),
                  ),
                  GoRoute(
                    path: 'add',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: NameForm(
                        title: c.l.newProfile,
                        action: 'saveProfile',
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'parental',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const ParentalControlPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'member/:id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: DetailPage(
                        collection: 'members',
                        id: s.pathParameters['id']!,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: ProfileManagePage(id: s.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: NameForm(
                            title: c.l.edit,
                            action: 'saveProfile',
                            id: s.pathParameters['id'],
                            initial: s.extra as String? ?? '',
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'favorites',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: ProfileDataPage(
                            profileId: s.pathParameters['id']!,
                          ),
                        ),
                      ),
                      GoRoute(
                        path: 'progress',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: ProfileDataPage(
                            profileId: s.pathParameters['id']!,
                            progress: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              GoRoute(
                path: '/family',
                // One account, one family: the Family tab is the only family screen.
                redirect: (c, s) => s.uri.path == '/family' ? '/users' : null,
                routes: [
                  GoRoute(
                    path: 'link-profile',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const ProfileLinkRedeemPage(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/devices',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const DeviceListPage()),
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (c, s) =>
                        _appPage(key: s.pageKey, child: const DeviceAddPage()),
                  ),
                  GoRoute(
                    path: 'scan',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const DeviceQrScannerPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'code',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const DeviceManualCodePage(),
                    ),
                  ),
                  GoRoute(
                    path: 'confirm',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const DeviceConfirmPairingPage(),
                    ),
                  ),
                  GoRoute(
                    path: 'success',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: DevicePairingSuccessPage(
                        deviceName: s.extra as String?,
                      ),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: DeviceDetailPage(
                        deviceId: s.pathParameters['id']!,
                      ),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: NameForm(
                            title: c.l.edit,
                            action: 'renameDevice',
                            id: s.pathParameters['id'],
                            initial: s.extra as String? ?? '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/iptv',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const ListIptvPage()),
                routes: [
                  GoRoute(
                    path: 'add',
                    pageBuilder: (c, s) =>
                        _appPage(key: s.pageKey, child: const IptvSourceForm()),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: IptvPage(id: s.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (c, s) => _appPage(
                          key: s.pageKey,
                          child: IptvSourceForm(
                            id: s.pathParameters['id'],
                            initialName: s.extra as String? ?? '',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/account',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const AccountPage()),
                routes: [
                  GoRoute(
                    path: 'settings',
                    pageBuilder: (c, s) =>
                        _appPage(key: s.pageKey, child: const SettingsPage()),
                  ),
                  GoRoute(
                    path: 'subscription',
                    pageBuilder: (c, s) => _appPage(
                      key: s.pageKey,
                      child: const SubscriptionPage(),
                    ),
                  ),
                  for (final kind in ['profile', 'help', 'about'])
                    GoRoute(
                      path: kind,
                      pageBuilder: (c, s) => _appPage(
                        key: s.pageKey,
                        child: InformationPage(kind: kind),
                      ),
                    ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/search',
                pageBuilder: (c, s) =>
                    _rootPage(key: s.pageKey, child: const SearchPage()),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
