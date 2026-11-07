import 'models.dart';

abstract class ManagerRepository {
  bool get configured;
  Stream<String?> authChanges();
  Future<void> initializeAccount(String uid);
  Stream<Account?> watchAccount(String uid);
  Stream<Family?> watchFamily(String id);
  Stream<List<Entry>> watchEntries(String familyId, String collection);
  Stream<Entry?> watchEntry(String familyId, String collection, String id);

  Future<void> signIn(String provider, {bool reauthenticate = false});

  /// Signs in with e-mail and password. There is no sign-up in the app: these
  /// accounts are created by the operator (store reviewers).
  Future<void> signInWithEmail(String email, String password);

  Future<void> sendPasswordReset(String email);

  /// Fresh login with the password, required before deleting the account.
  Future<void> reauthenticate(String password);

  /// True when the current account signs in with e-mail and password.
  bool get signedInWithPassword;
  Future<void> signOut();
  Future<void> deleteAccount();
  Future<Map<String, dynamic>> mutate(
    String action, [
    Map<String, dynamic> payload = const {},
  ]);
  Future<CatalogPage> catalog(
    String familyId,
    Entry source,
    String search, {
    Object? cursor,
  });
}
