// lib/services/update_service.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';

class UpdateInfo {
  final int remoteVersionCode;
  final String downloadUrl;
  final String? changelog;

  UpdateInfo({required this.remoteVersionCode, required this.downloadUrl, this.changelog});
}

class UpdateService {
  // Replace with your hosted JSON URL
  static const String updateConfigUrl = 'https://my-server.com/app/version.json';

  Future<int> _getCurrentVersionCode() async {
    final info = await PackageInfo.fromPlatform();
    // buildNumber is string; parse to int
    final build = int.tryParse(info.buildNumber) ?? 0;
    return build;
  }

  Future<UpdateInfo?> checkForUpdate({String? overrideUrl}) async {
    if (!kIsWeb && Platform.isAndroid) {
      final configUrl = overrideUrl ?? updateConfigUrl;
      final resp = await http.get(Uri.parse(configUrl));
      if (resp.statusCode != 200) return null;
      final Map<String, dynamic> jsonMap = json.decode(resp.body);
      final remoteVersion = (jsonMap['versionCode'] is int)
          ? jsonMap['versionCode'] as int
          : int.tryParse('${jsonMap['versionCode']}') ?? 0;
      final downloadUrl = jsonMap['downloadUrl'] as String?;
      final changelog = jsonMap['changelog'] as String?;

      if (downloadUrl == null) return null;

      final current = await _getCurrentVersionCode();
      if (remoteVersion > current) {
        return UpdateInfo(remoteVersionCode: remoteVersion, downloadUrl: downloadUrl, changelog: changelog);
      }
    }
    return null;
  }

  Future<File> downloadApk(String downloadUrl, {void Function(int received, int total)? onProgress}) async {
    if (!Platform.isAndroid) throw UnsupportedError('APK download only supported on Android');

    final client = http.Client();
    final req = http.Request('GET', Uri.parse(downloadUrl));
    final streamed = await client.send(req);

    if (streamed.statusCode != 200) {
      throw HttpException('Failed to download APK: ${streamed.statusCode}');
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/update.apk');
    final sink = file.openWrite();

    final contentLength = streamed.contentLength ?? 0;
    int received = 0;

    await for (final chunk in streamed.stream) {
      received += chunk.length;
      sink.add(chunk);
      if (onProgress != null) onProgress(received, contentLength);
    }

    await sink.close();
    client.close();
    return file;
  }

  Future<void> installApk(File apkFile) async {
    if (!Platform.isAndroid) throw UnsupportedError('APK install only supported on Android');

    // Use open_filex to open the APK which triggers the system installer
    await OpenFilex.open(apkFile.path);
  }
}
