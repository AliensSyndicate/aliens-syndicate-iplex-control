import 'package:flutter/material.dart';

class RouterRefresh extends ChangeNotifier {
  bool _scheduled = false;
  bool _disposed = false;
  // Auth, account and family can change in the same frame. Reparse once after
  // those updates settle rather than racing redirects from an old location.
  void refresh() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
