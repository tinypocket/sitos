import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// Notifies listeners (e.g. go_router) whenever the signed-in account changes.
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
    await _signIn.initialize(serverClientId: serverClientId);
    _signIn.authenticationEvents.listen(_onEvent).onError((Object _) {
      account.value = null;
      _googleIdToken = null;
    });
    // Silent restore of a previous session, if any. Failures are non-fatal.
    try {
      await _signIn.attemptLightweightAuthentication();
    } catch (_) {/* no existing session */}
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    final user = switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };
    _googleIdToken = user?.authentication.idToken;
    account.value = user;
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
    _googleIdToken = null;
    account.value = null;
  }
}
