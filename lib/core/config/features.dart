/// Product switches of the Control.
abstract final class Features {
  /// Kids profiles ("Conta infantil"): there is no children's content yet,
  /// so everything about them is hidden in the Control (the invite option,
  /// the profile type, the profile toggle and the Help answers). Nothing is
  /// removed: turning this on brings it all back. Profiles that are already
  /// Kids keep working and keep their label; the backend rules are
  /// unchanged.
  static const kidsProfiles = false;
}
