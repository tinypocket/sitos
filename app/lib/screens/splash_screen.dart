import 'package:flutter/material.dart';

/// Shown while we silently restore a saved session on launch, so a signed-in user never
/// sees the login screen flash. Matches the login screen's branding.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final green = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: green,
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('S',
                style: TextStyle(
                    fontSize: 120, fontWeight: FontWeight.bold, color: Colors.white)),
            SizedBox(height: 4),
            Text('Sitos',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600, color: Colors.white)),
            SizedBox(height: 40),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
