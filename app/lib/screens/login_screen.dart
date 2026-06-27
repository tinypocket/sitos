import 'package:flutter/material.dart';

import '../auth_service.dart';

/// Branded sign-in screen. Tapping the button triggers the native Google account picker;
/// on success the auth state changes and go_router redirects into the app.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService.instance.signIn();
    } catch (e) {
      if (mounted) setState(() => _error = 'Sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: green,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('S',
                  style: TextStyle(
                      fontSize: 120, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Sitos',
                  style: TextStyle(
                      fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
              const SizedBox(height: 8),
              const Text('Scan. Log. Track.',
                  style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 64),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 12),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _busy ? null : _signIn,
                icon: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.login),
                label: const Text('Sign in with Google'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
