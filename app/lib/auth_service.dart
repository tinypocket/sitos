import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Gate state. `unknown` means we haven't finished checking for a saved session yet —
/// the router shows a splash for this, NOT the login screen, so a signed-in user never
/// sees the sign-in button flash on launch.
enum AuthStatus { unknown, signedIn, signedOut }

/// Direct Google Sign-In. The signed-in account's ID token is sent to the Sitos API as a
/// Bearer token; the API validates it against Google.
///
/// Two build-time switches:
///  - `SITOS_GOOGLE_SERVER_CLIENT_ID` (Google web client id) enables the real Google login gate.
///  - `SITOS_TEST_TOKEN` enables **test mode**: the login gate is skipped and the given token is
///    sent instead, so features can be exercised on an emulator without interactive sign-in. The
///    API must have a matching `Auth:TestToken` (dev/staging only). Real Google login is unaffected.
///
/// With neither set (plain local dev against a no-auth API), the app skips the gate and the API
/// uses its dev user.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// The Google OAuth **web** client id. Its value becomes the `aud` of the ID token.
  static const String serverClientId =
      String.fromEnvironment('SITOS_GOOGLE_SERVER_CLIENT_ID');

  /// When set, skip Google sign-in and send this as the bearer token (test mode).
  static const String _testToken = String.fromEnvironment('SITOS_TEST_TOKEN');
  static bool get testMode => _testToken.isNotEmpty;

  /// The real-Google login gate is active only outside test mode.
  static bool get enabled => serverClientId.isNotEmpty && !testMode;

  final GoogleSignIn _signIn = GoogleSignIn.instance;

  /// Drives go_router. Starts `unknown` until the first silent-restore attempt settles, so the
  /// gate shows a splash instead of the login screen while we're still restoring the session.
  final ValueNotifier<AuthStatus> status = ValueNotifier(AuthStatus.unknown);

  /// The signed-in account (null when signed out). Kept for any UI that wants the profile.
  final ValueNotifier<GoogleSignInAccount?> account = ValueNotifier(null);

  String? _googleIdToken;

  /// The bearer token attached to API requests: the test token in test mode, otherwise the
  /// current Google ID token (null when signed out).
  String? get idToken => testMode ? _testToken : _googleIdToken;

  Future<void>? _initFuture;

  /// Idempotent: starts Google initialization once and returns the same future thereafter.
  /// In test mode (or plain dev) there is no Google session to initialise.
  Future<void> ensureInitialized() {
    if (!enabled) return Future.value();
    return _initFuture ??= _init();
  }

  Future<void> _init() async {
    try {
      await _signIn.initialize(serverClientId: serverClientId);
    } catch (_) {
      // Don't strand the app on the splash if Google init itself fails.
      _setSignedOut();
      return;
    }
    _signIn.authenticationEvents.listen(_onEvent).onError((Object _) => _setSignedOut());
    await _attemptSilentRestore();
  }

  /// Try to restore a previous session without any UI. Bounded by a timeout because this can
  /// hang on some devices — a hang must resolve the gate to signed-out, never leave it stuck
  /// on the splash. We use the return value directly (not just the event stream) for reliability.
  Future<void> _attemptSilentRestore() async {
    try {
      final pending = _signIn.attemptLightweightAuthentication();
      final user =
          pending == null ? null : await pending.timeout(const Duration(seconds: 8));
      if (user != null) {
        _setSignedIn(user);
        return;
      }
    } catch (_) {
      // No existing session, or the silent attempt timed out / errored.
    }
    // Only settle to signed-out if an auth event hasn't already signed us in.
    if (account.value == null) _setSignedOut();
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn():
        _setSignedIn(event.user);
      case GoogleSignInAuthenticationEventSignOut():
        _setSignedOut();
    }
  }

  void _setSignedIn(GoogleSignInAccount user) {
    _googleIdToken = user.authentication.idToken;
    account.value = user;
    status.value = AuthStatus.signedIn;
  }

  void _setSignedOut() {
    _googleIdToken = null;
    account.value = null;
    status.value = AuthStatus.signedOut;
  }

  /// Interactive sign-in. Ensures initialization completed first.
  Future<void> signIn() async {
    await ensureInitialized();
    if (_signIn.supportsAuthenticate()) {
      await _signIn.authenticate();
    }
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    _setSignedOut();
  }
}
