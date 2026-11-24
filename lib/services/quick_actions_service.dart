import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

class QuickActionsService {
  static final QuickActionsService instance = QuickActionsService._internal();
  QuickActionsService._internal();

  final QuickActions _quickActions = const QuickActions();
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  void initialize() {
    try {
      // Clear app icon shortcuts
      _quickActions.setShortcutItems(<ShortcutItem>[]);
    } catch (e) {
      debugPrint('QuickActions init error: $e');
    }
  }
}
