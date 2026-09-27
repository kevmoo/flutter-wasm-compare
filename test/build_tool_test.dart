import 'package:flutter_test/flutter_test.dart';

import '../tool/build.dart';

void main() {
  group('FlutterVersionInfo.fromJson', () {
    test('parses standard 3.x --version --machine payload', () {
      final json = {
        'frameworkVersion': '3.49.0-1.0.pre',
        'channel': 'master',
        'repositoryUrl': 'https://github.com/flutter/flutter.git',
        'frameworkRevision': '1234567890abcdef',
        'engineRevision': 'fedcba0987654321',
        'dartSdkVersion': '3.8.0 (build 3.8.0-16.0.dev)',
        'devToolsVersion': '2.42.0',
      };

      final info = FlutterVersionInfo.fromJson(json);
      expect(info.frameworkVersion, '3.49.0-1.0.pre');
      expect(info.frameworkRevision, '1234567890abcdef');
      expect(info.engineRevision, 'fedcba0987654321');
      expect(info.dartSdkVersion, '3.8.0');
    });

    test('handles missing or empty fields correctly', () {
      final json = <String, dynamic>{};

      final info = FlutterVersionInfo.fromJson(json);
      expect(info.frameworkVersion, '');
      expect(info.frameworkRevision, '');
      expect(info.engineRevision, '');
      expect(info.dartSdkVersion, '');
    });
  });
}
