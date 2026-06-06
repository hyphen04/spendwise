import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum InstallResult {
  /// System package installer launched successfully.
  launched,
  /// User has not granted REQUEST_INSTALL_PACKAGES — settings were opened.
  permissionDenied,
  /// The APK file was not found on disk.
  fileNotFound,
  /// OpenFile returned an error (wrong MIME, corrupt file, etc.).
  error,
}

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseNotes,
    required this.apkUrl,
    required this.apkSize,
  });

  final String version;      // "2.1.0"
  final String tagName;      // "v2.1.0"
  final String releaseNotes; // GitHub release body (markdown text)
  final String apkUrl;       // direct download URL for .apk asset
  final int apkSize;         // bytes (0 if unknown)
}

class DownloadProgress {
  const DownloadProgress({required this.progress, this.filePath});

  final double progress;  // 0.0 – 1.0
  final String? filePath; // set only on the final event (progress == 1.0)
}

class UpdateService {
  static const _owner = 'hyphen04';
  static const _repo = 'spendwise';
  static const _prefKey = 'pending_apk_cleanup';
  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Checks GitHub for the latest release.
  /// Returns [UpdateInfo] if a newer version exists, null if already up to date.
  /// Throws on network error or unexpected API response.
  static Future<UpdateInfo?> checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final response = await http
        .get(Uri.parse(_apiUrl),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 15));

    if (response.statusCode == 404) {
      throw Exception('No releases found on GitHub yet.');
    }
    if (response.statusCode != 200) {
      throw Exception('GitHub returned ${response.statusCode}. Try again later.');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final tagName = data['tag_name'] as String? ?? '';
    final releaseNotes = (data['body'] as String? ?? '').trim();
    final assets = data['assets'] as List<dynamic>? ?? [];

    if (tagName.isEmpty) throw Exception('Malformed release data from GitHub.');
    if (!_isNewer(tagName, info.version)) return null;

    final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => {},
        );
    if (apkAsset.isEmpty) {
      throw Exception(
          'Release $tagName exists but has no APK asset attached yet.');
    }

    return UpdateInfo(
      version: tagName.startsWith('v') ? tagName.substring(1) : tagName,
      tagName: tagName,
      releaseNotes: releaseNotes,
      apkUrl: apkAsset['browser_download_url'] as String,
      apkSize: apkAsset['size'] as int? ?? 0,
    );
  }

  /// Downloads the APK from [info], streaming progress events.
  /// The final event has [DownloadProgress.filePath] set.
  static Stream<DownloadProgress> downloadApk(UpdateInfo info) async* {
    final dir = await getTemporaryDirectory();
    final apkDir = Directory('${dir.path}/apk_downloads');
    await apkDir.create(recursive: true);
    final file = File('${apkDir.path}/spendwise-update.apk');
    if (await file.exists()) await file.delete();

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await client.send(request);
      final total = response.contentLength ?? info.apkSize;
      int received = 0;

      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        yield DownloadProgress(
          progress: total > 0 ? (received / total).clamp(0.0, 0.99) : 0.0,
        );
      }
      await sink.flush();
      await sink.close();

      // Record path for cleanup on next launch
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, file.path);

      yield DownloadProgress(progress: 1.0, filePath: file.path);
    } catch (e) {
      try { await file.delete(); } catch (_) {}
      rethrow;
    } finally {
      client.close();
    }
  }

  /// Requests install permission if needed, then launches the system package
  /// installer. Returns an [InstallResult] describing what happened.
  ///
  /// On Android 8+, REQUEST_INSTALL_PACKAGES is a special runtime permission —
  /// the manifest entry is not enough. Calling `.request()` opens the
  /// "Allow from this source" Settings screen; the user must enable it and
  /// return to the app before tapping Install again.
  static Future<InstallResult> installApk(String filePath) async {
    if (!await File(filePath).exists()) return InstallResult.fileNotFound;

    if (Platform.isAndroid) {
      var status = await Permission.requestInstallPackages.status;
      if (!status.isGranted) {
        // Opens "Install unknown apps" settings for this app.
        status = await Permission.requestInstallPackages.request();
        if (!status.isGranted) {
          return InstallResult.permissionDenied;
        }
      }
    }

    final result = await OpenFile.open(
      filePath,
      type: 'application/vnd.android.package-archive',
    );

    switch (result.type) {
      case ResultType.done:
        return InstallResult.launched;
      case ResultType.permissionDenied:
        return InstallResult.permissionDenied;
      default:
        return InstallResult.error;
    }
  }

  /// Call at app startup to delete any leftover APK from a previous update.
  /// The new version's first launch handles cleanup because the old process
  /// is replaced by the installer before it can clean up itself.
  static Future<void> cleanupPendingApk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString(_prefKey);
      if (path == null) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
      await prefs.remove(_prefKey);
    } catch (_) {
      // Non-critical — silently ignore
    }
  }

  // ── Private helpers ─────────────────────────────────────────────────────────

  /// Returns true if [tagName] (e.g. "v2.1.0") is newer than [currentVersion]
  /// (e.g. "2.0.0" from pubspec, may include build number like "2.0.0+2").
  static bool _isNewer(String tagName, String currentVersion) {
    final tag = tagName.startsWith('v') ? tagName.substring(1) : tagName;
    // Strip build number from current version
    final cur = currentVersion.split('+').first;

    final tagParts = tag.split('.').map(_toInt).toList();
    final curParts = cur.split('.').map(_toInt).toList();

    for (var i = 0; i < 3; i++) {
      final t = i < tagParts.length ? tagParts[i] : 0;
      final c = i < curParts.length ? curParts[i] : 0;
      if (t > c) return true;
      if (t < c) return false;
    }
    return false; // equal
  }

  static int _toInt(String s) => int.tryParse(s.trim()) ?? 0;
}
