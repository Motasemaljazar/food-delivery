import '../models/app_state.dart';
import 'api.dart';

/// Lightweight global references used for push-notification deep linking.
/// This keeps the existing architecture (no new projects/stack changes).
class AppRefs {
  static AppState? state;
  static ApiClient? api;
}
