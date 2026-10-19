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
