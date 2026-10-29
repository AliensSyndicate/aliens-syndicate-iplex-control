import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/models.dart';
import '../domain/repository.dart';
import 'callable_failure.dart';

class FirebaseManagerRepository implements ManagerRepository {
  FirebaseManagerRepository({required this.configured});
  @override
  final bool configured;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;
  String? _provider;
  String? _contextFamilyId;

  /// Family context sent with every manager call (null = personal scope).
  String? get contextFamilyId => _contextFamilyId;
  String? _pushToken;
  Future<void>? _googleInitialization;
  @override
  Stream<String?> authChanges() => configured
      ? _auth.authStateChanges().map((u) => u?.uid)
      : Stream.value(null);
  @override
  Stream<Account?> watchAccount(String uid) =>
      _db.doc('users/$uid').snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        _contextFamilyId = d['familyId'] as String?;
        return Account(
          uid: uid,
          name: (d['displayName'] ?? d['name'] ?? '') as String,
          email: d['email'] as String? ?? '',
          familyId: d['familyId'] as String?,
          familyIds: List<String>.from(d['familyIds'] as List? ?? const []),
          publicCode: d['publicCode'] as String?,
          // The stored photo is the sign-in provider's; Auth is only a fallback for the
          // short time before the backend has copied it.
          photoUrl: _httpsPhoto(
            d['photoUrl'] ??
                (_auth.currentUser?.uid == uid
                    ? _auth.currentUser?.photoURL
                    : null),
          ),
          iptvWorkspaceId: d['iptvWorkspaceId'] as String?,
          locale: d['locale'] as String? ?? 'system',
        );
      });
  static String? _httpsPhoto(Object? value) =>
      value is String && value.startsWith('https://') ? value : null;
  @override
  Stream<Family?> watchFamily(String id) =>
      _db.doc('families/$id').snapshots().map((s) {
        final d = s.data();
        if (d == null) return null;
        final rawAdmin = d['adminUid'] ?? d['adminId'] ?? '';
        final rawMembers = d['members'] != null
            ? Map<String, String>.from(d['members'] as Map)
            : <String, String>{};
        return Family(
          id: id,
          adminId: rawAdmin as String,
          name: d['name'] as String? ?? '',
          individual: d['individual'] == true,
          members: rawMembers,
          parentalPinConfigured:
              (d['parental'] as Map?)?['pinConfigured'] == true,
        );
      });
  @override
  Stream<List<Entry>> watchEntries(String familyId, String collection) =>
      (collection == 'invitations'
              ? _db
                    .collection('family_requests')
                    .where('recipientUid', isEqualTo: familyId)
                    .where('status', isEqualTo: 'pending')
              : collection == 'sentInvitations'
              ? _db
                    .collection('family_requests')
                    .where('familyId', isEqualTo: familyId)
                    .where('status', isEqualTo: 'pending')
              : _db.collection('families/$familyId/$collection'))
          .limit(100)
          .snapshots()
          .map(
            (s) => s.docs
                .map((d) => Entry(d.id, d.data()))
                .toList(growable: false),
          );
  @override
  Stream<Entry?> watchEntry(String familyId, String collection, String id) =>
      _db
          .doc('families/$familyId/$collection/$id')
          .snapshots()
          .map((d) => d.exists ? Entry(d.id, d.data()!) : null);
  static const String _defaultServerClientId =
      '59148444884-8baaa8slbvov2dhg7d5ig3kv4gnkgv37.apps.googleusercontent.com';

  Future<void> _initializeGoogle() {
    final serverClientId =
        const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID').isNotEmpty
        ? const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')
        : _defaultServerClientId;
    return _googleInitialization ??= GoogleSignIn.instance.initialize(
      serverClientId: serverClientId,
    );
  }

  @override
  Future<void> signIn(String provider, {bool reauthenticate = false}) async {
    if (!configured) throw const AppFailure('configuration-required');
    try {
      if (provider == 'anonymous') {
        await _auth.signInAnonymously();
      } else if (provider == 'google' && !kIsWeb) {
        await _initializeGoogle();
        final user = await GoogleSignIn.instance.authenticate();
        final credential = GoogleAuthProvider.credential(
          idToken: user.authentication.idToken,
        );
        if (reauthenticate) {
          await _auth.currentUser!.reauthenticateWithCredential(credential);
        } else {
          await _auth.signInWithCredential(credential);
        }
      } else {
        final AuthProvider authProvider = provider == 'apple'
            ? AppleAuthProvider()
            : GoogleAuthProvider();
        if (reauthenticate) {
          await _auth.currentUser!.reauthenticateWithProvider(authProvider);
        } else if (kIsWeb) {
          await _auth.signInWithPopup(authProvider);
        } else {
          await _auth.signInWithProvider(authProvider);
        }
      }
      _provider = provider;
    } on FirebaseAuthException catch (e) {
      throw AppFailure(e.code);
    } on GoogleSignInException catch (e) {
      throw AppFailure(
        e.code == GoogleSignInExceptionCode.canceled
            ? 'cancelled'
            : 'sign-in-failed',
      );
    }
  }

  @override
  Future<void> initializeAccount(String uid) async {
    if (!configured) throw const AppFailure('configuration-required');
    final user = _auth.currentUser;
    if (user == null || user.uid != uid) {
      throw const AppFailure('requires-recent-login');
    }
    await mutate('bootstrap');
  }

  @override
  Future<void> signOut() async {
    if (!kIsWeb && _auth.currentUser != null) {
      try {
        final token = _pushToken;
        if (token != null) {
          await mutate('unregisterPushToken', {'token': token});
        }
        await FirebaseMessaging.instance.unregister();
        _pushToken = null;
      } catch (_) {
        /* Logout remains available offline. */
      }
    }
    await _auth.signOut();
    if (!kIsWeb) {
      // Also after an app restart, so the next login shows the account picker.
      try {
        await _initializeGoogle();
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        /* Not signed in with Google on this device. */
      }
    }
  }

  @override
  Future<void> deleteAccount() async {
    final provider =
        _provider ??
        (_auth.currentUser?.providerData.any(
                  (p) => p.providerId == 'apple.com',
                ) ==
                true
            ? 'apple'
            : 'google');
    // One fresh login. Apple's revocation needs the authorization code of
    // that same login, so Apple reauthenticates here instead of in signIn.
    String? appleCode;
    if (provider == 'apple' && !kIsWeb) {
      try {
        final result = await _auth.currentUser!.reauthenticateWithProvider(
          AppleAuthProvider(),
        );
        appleCode = result.additionalUserInfo?.authorizationCode;
      } on FirebaseAuthException catch (e) {
        throw AppFailure(e.code);
      }
      if (appleCode == null) {
        throw const AppFailure('apple-revocation-required');
      }
    } else {
      await signIn(provider, reauthenticate: true);
    }
    // The backend validates first (recent login, family without members):
    // nothing is revoked or deleted if it refuses.
    await mutate('prepareDeletion');
    if (appleCode != null) {
      try {
        await _auth.revokeTokenWithAuthorizationCode(appleCode);
      } catch (_) {
        /* The account is already scheduled for deletion. */
      }
    }
    try {
      await _auth.currentUser?.delete();
    } catch (_) {
      // The scheduled deletion job removes the authentication account too.
    }
    await signOut();
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (!configured) throw const AppFailure('configuration-required');
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
            'manager',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
          )
          .call<dynamic>({
            'action': action,
            'payload': {'contextFamilyId': _contextFamilyId, ...payload},
          });
      if (action == 'registerPushToken') {
        _pushToken = payload['token'] as String?;
      }
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'unauthenticated' && _auth.currentUser != null) {
        // The callable answers `unauthenticated` both for an invalid ID token
        // and for a missing/invalid App Check token (enforceAppCheck). A
        // successful forced refresh proves the Firebase session is valid, so a
        // second rejection is an app-verification failure, never a reason to
        // ask for a new login or to end the session.
        try {
          await _auth.currentUser!.getIdToken(true);
        } on FirebaseAuthException catch (authError) {
          throw AppFailure(
            authError.code == 'network-request-failed'
                ? 'network-request-failed'
                : 'requires-recent-login',
          );
        }
        // The retry must not reuse an expired or placeholder App Check token
        // (the SDK sends a placeholder when an attestation refresh failed).
        // The backend still verifies whatever comes back.
        try {
          await FirebaseAppCheck.instance.getToken(true);
        } catch (_) {
          // Attestation still unavailable: the retry reports app-verification-failed.
        }
        try {
          final retryResult =
              await FirebaseFunctions.instanceFor(region: 'us-central1')
                  .httpsCallable(
                    'manager',
                    options: HttpsCallableOptions(
                      timeout: const Duration(seconds: 30),
                    ),
                  )
                  .call<dynamic>({
                    'action': action,
                    'payload': {
                      'contextFamilyId': _contextFamilyId,
                      ...payload,
                    },
                  });
          return Map<String, dynamic>.from(retryResult.data as Map);
        } on FirebaseFunctionsException catch (retryError) {
          if (retryError.code != 'unauthenticated') {
            throw callableFailure(
              code: retryError.code,
              message: retryError.message,
              details: retryError.details,
            );
          }
          if (kDebugMode) {
            // Safe diagnostic: action and code only, no tokens or user data.
            debugPrint(
              'manager/$action rejected with a valid ID token: '
              'App Check verification failed.',
            );
          }
          throw const AppFailure('app-verification-failed');
        }
      }
      throw callableFailure(
        code: e.code,
        message: e.message,
        details: e.details,
      );
    }
  }

  @override
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  }) async {
    if (source.text('catalogStorage') == 'object') {
      final result = await mutate('readSourceCatalog', {
        'id': source.id,
        'version': source.text('version'),
        'search': search,
        'cursor': cursor ?? 0,
      });
      return CatalogPage(
        (result['items'] as List).map((row) {
          final data = Map<String, dynamic>.from(row as Map);
          return Entry(data['id'] as String, data);
        }).toList(),
        result['cursor'],
        result['hasMore'] == true,
      );
    }
    final version = source.text('version');
    if (version.isEmpty) return const CatalogPage([], null, false);
    Query<Map<String, dynamic>> query = _db
        .collection('families/$familyId/catalog')
        .where('version', isEqualTo: version)
        .where('sourceId', isEqualTo: source.id)
        .orderBy('titleKey');
    final key = search.trim().toLowerCase();
    if (key.isNotEmpty) query = query.startAt([key]).endAt(['$key\uf8ff']);
    if (cursor != null) {
      query = query.startAfterDocument(
        cursor as DocumentSnapshot<Map<String, dynamic>>,
      );
    }
    final result = await query.limit(30).get();
    return CatalogPage(
      result.docs
          .map((d) => Entry(d.data()['id'] as String, d.data()))
          .toList(),
      result.docs.lastOrNull,
      result.docs.length == 30,
    );
  }
}
