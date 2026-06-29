import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Developer / experimental toggles, persisted locally via SharedPreferences.
/// These gate in-progress features so we can try them on a device without
/// shipping them to everyone. Surfaced under a "Developer" section in Settings.
class DevSettings {
  final bool multiScan;

  const DevSettings({this.multiScan = false});

  DevSettings copyWith({bool? multiScan}) =>
      DevSettings(multiScan: multiScan ?? this.multiScan);
}

class DevSettingsNotifier extends Notifier<DevSettings> {
  static const _kMultiScan = 'dev.multiScan';
  SharedPreferences? _prefs;

  @override
  DevSettings build() {
    // Default off; hydrate asynchronously and emit the stored values once loaded.
    _load();
    return const DevSettings();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    state = DevSettings(multiScan: _prefs!.getBool(_kMultiScan) ?? false);
  }

  Future<void> setMultiScan(bool value) async {
    state = state.copyWith(multiScan: value);
    (_prefs ??= await SharedPreferences.getInstance())
        .setBool(_kMultiScan, value);
  }
}

final devSettingsProvider =
    NotifierProvider<DevSettingsNotifier, DevSettings>(DevSettingsNotifier.new);
