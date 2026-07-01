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

/// Depth for the photo-capture flow (E4): [breakdown] returns many ingredient
/// rows, [estimate] returns a single whole-dish row. Mapped 1:1 to the
/// `parsePhoto` API `mode` value.
enum PhotoDepth {
  breakdown,
  estimate;

  String get label => switch (this) {
        PhotoDepth.breakdown => 'Breakdown',
        PhotoDepth.estimate => 'Estimate',
      };

  /// The API `mode` string for `SitosApi.parsePhoto`.
  String get mode => name; // 'breakdown' | 'estimate'
}

/// Remembers the user's last photo-capture depth choice across launches.
class PhotoDepthNotifier extends Notifier<PhotoDepth> {
  static const _kKey = 'photo.depth';
  SharedPreferences? _prefs;

  @override
  PhotoDepth build() {
    // Default to Breakdown; hydrate the stored choice asynchronously.
    _load();
    return PhotoDepth.breakdown;
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs!.getString(_kKey);
    state = PhotoDepth.values.firstWhere(
      (d) => d.name == stored,
      orElse: () => PhotoDepth.breakdown,
    );
  }

  Future<void> set(PhotoDepth depth) async {
    state = depth;
    (_prefs ??= await SharedPreferences.getInstance())
        .setString(_kKey, depth.name);
  }
}

final photoDepthProvider =
    NotifierProvider<PhotoDepthNotifier, PhotoDepth>(PhotoDepthNotifier.new);
