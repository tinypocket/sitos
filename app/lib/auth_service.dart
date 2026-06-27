import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Direct Google Sign-In. The signed-in account's ID token is sent to the Sitos API as a
/// Bearer token; the API validates it against Google.
///
/// Auth is enabled only when [serverClientId] is provided via
/// `--dart-define=SITOS_GOOGLE_SERVER_CLIENT_ID=<google web client id>`. With it empty (e.g.
/// local dev against a no-auth API), the app skips the login gate and the API uses its dev user.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  /// The Google OAuth **web** client id. Its value becomes the `aud` of the ID token, which the
  /// API validates. Empty => auth disabled.
  static const String serverClientId =
      String.fromEnvironment('SITOS_GOOGLE_SERVER_CLIENT_ID');

  static bool get enabled => serverClientId.isNotEmpty;

  final GoogleSignIn _signIn = GoogleSignIn.instance;

  /// Notifies listeners (e.g. go_router) whenever the signed-in account changes.
  final ValueNotifier<GoogleSignInAccount?> account = ValueNotifier(null);

  /// The current Google ID token, attached to API requests. Null when signed out.
  String? idToken;

  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized || !enabled) return;
    _initialized = true;

    await _signIn.initialize(serverClientId: serverClientId);
    _signIn.authenticationEvents.listen(_onEvent).onError((Object _) {
      account.value = null;
      idToken = null;
    });
    // Silent restore of a previous session, if any.
    await _signIn.attemptLightweightAuthentication();
  }

  void _onEvent(GoogleSignInAuthenticationEvent event) {
    final user = switch (event) {
      GoogleSignInAuthenticationEventSignIn() => event.user,
      GoogleSignInAuthenticationEventSignOut() => null,
    };
    idToken = user?.authentication.idToken;
    account.value = user;
  }

  /// Interactive sign-in. Safe to call only where the platform supports it.
  Future<void> signIn() async {
    if (_signIn.supportsAuthenticate()) {
      await _signIn.authenticate();
    }
  }

  Future<void> signOut() async {
    await _signIn.signOut();
    idToken = null;
    account.value = null;
  }
}
