import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('startup secret boundary', () {
    test('does not load or package a root environment file', () {
      final pubspec = _read('pubspec.yaml');
      final main = _read('lib/main.dart');

      expect(File('.env').existsSync(), isFalse);
      expect(pubspec, isNot(contains('flutter_dotenv')));
      expect(pubspec, isNot(contains('- .env')));
      expect(main, isNot(contains('dotenv')));
    });

    test('keeps Administrator credentials out of Flutter source', () {
      final flutterSource = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      expect(flutterSource, isNot(contains('GOOGLE_APPLICATION_CREDENTIALS')));
      expect(flutterSource, isNot(contains('BOOTSTRAP_ADMIN_UID')));
      expect(flutterSource, isNot(contains('firebase-admin')));
    });
  });

  group('authentication boundary', () {
    test('SQLite and Flutter no longer implement password verifiers', () {
      final schema = _read('lib/database/database_helper.dart');
      final localUsers = _read('lib/repositories/local_user_repository.dart');

      expect(schema, isNot(contains('password TEXT')));
      expect(localUsers, isNot(contains('PBKDF2')));
      expect(localUsers, isNot(contains('_verify')));
      expect(localUsers, isNot(contains('password')));
    });

    test('cloud paths use Firebase UID and rules protect access state', () {
      final sync = _read('lib/repositories/firestore_sync.dart');
      final rules = _read('firestore.rules');

      expect(sync, contains('principal.uid != uid'));
      expect(rules, contains('accountAccess'));
      expect(rules, contains("status == 'approved'"));
      expect(rules, contains("role == 'Administrator'"));
      expect(rules, contains("sign_in_provider != 'anonymous'"));
    });

    test('legacy custom-password Functions are removed', () {
      expect(File('functions/auth_helpers.js').existsSync(), isFalse);
      expect(File('functions/index.js').existsSync(), isFalse);
    });

    test('Administrator bootstrap preserves username reservations', () {
      final bootstrap = _read('functions/scripts/bootstrap_admin.js');

      expect(bootstrap, contains('usernameReservation.exists'));
      expect(bootstrap, contains("usernameReservation.data().uid !== uid"));
      expect(bootstrap, contains('this username is already reserved'));
    });

    test('Spark registration has no callable Functions path', () {
      final cloudAuth = _read('lib/services/cloud_auth_service.dart');
      final rules = _read('firestore.rules');

      for (final endpoint in [
        'submitRegistrationRequest',
        'refreshRegistrationVerification',
        'reviewRegistrationRequest',
      ]) {
        expect(cloudAuth, isNot(contains(endpoint)));
      }
      expect(File('functions/index.js').existsSync(), isFalse);
      expect(cloudAuth, isNot(contains('http.post')));
      expect(cloudAuth, contains("collection('accountAccess')"));
      expect(cloudAuth, contains("collection('_usernames')"));
      expect(rules, contains('request.auth.token.email_verified == true'));
      expect(rules, contains('getAfter('));
    });
  });

  group('reproducible toolchains', () {
    test('pins the Flutter SDK used by CI', () {
      final fvm = jsonDecode(_read('.fvmrc')) as Map<String, dynamic>;
      final workflow = _read('.github/workflows/ci.yml');
      final pubspec = _read('pubspec.yaml');
      final lockfile = _read('pubspec.lock');

      expect(fvm['flutter'], '3.38.4');
      expect(workflow, contains('flutter-version: 3.38.4'));
      expect(pubspec, contains("flutter: '>=3.38.4'"));
      expect(pubspec, contains("sdk: '>=3.10.3 <4.0.0'"));
      expect(lockfile, contains(r'dart: ">=3.10.3 <4.0.0"'));
      expect(lockfile, contains(r'flutter: ">=3.38.4"'));
    });

    test('CI enforces the documented coverage floor', () {
      final workflow = _read('.github/workflows/ci.yml');
      final checker = _read('tool/check_coverage.dart');

      expect(
        workflow,
        contains('dart run tool/check_coverage.dart coverage/lcov.info 30'),
      );
      expect(checker, contains('percentage < threshold'));
    });

    test('uses locked Firebase Administrator dependencies', () {
      expect(File('functions/package-lock.json').existsSync(), isTrue);
      expect(_read('.github/workflows/ci.yml'), contains('run: npm ci'));
    });

    test('keeps the Gradle wrapper available to clean checkouts', () {
      expect(File('android/gradlew').existsSync(), isTrue);
      expect(File('android/gradlew.bat').existsSync(), isTrue);
      expect(
        File('android/gradle/wrapper/gradle-wrapper.jar').existsSync(),
        isTrue,
      );

      final androidIgnores = _read('android/.gitignore');
      expect(androidIgnores, isNot(contains('/gradlew')));
      expect(androidIgnores, isNot(contains('gradle-wrapper.jar')));
    });
  });

  group('release configuration', () {
    test(
      'Android uses the branded package ID and never debug-signs release',
      () {
        final gradle = _read('android/app/build.gradle.kts');

        expect(gradle, contains('com.knzscent.admin'));
        expect(gradle, isNot(contains('signingConfigs.getByName("debug")')));
        expect(gradle, contains('ANDROID_KEYSTORE_PATH'));
      },
    );

    test('Android requests no exact-alarm or reboot scheduling capability', () {
      final manifest = _read('android/app/src/main/AndroidManifest.xml');

      expect(manifest, isNot(contains('USE_EXACT_ALARM')));
      expect(manifest, isNot(contains('RECEIVE_BOOT_COMPLETED')));
      expect(manifest, isNot(contains('ScheduledNotificationReceiver')));
    });

    test('iOS declares every privacy purpose used by the app', () {
      final infoPlist = _read('ios/Runner/Info.plist');

      expect(infoPlist, contains('NSBluetoothAlwaysUsageDescription'));
      expect(infoPlist, contains('NSCameraUsageDescription'));
      expect(infoPlist, contains('NSPhotoLibraryUsageDescription'));
    });

    test('web manifest contains KNZ branding', () {
      final manifest =
          jsonDecode(_read('web/manifest.json')) as Map<String, dynamic>;

      expect(manifest['name'], 'KNZ Scent Admin');
      expect(manifest['short_name'], 'KNZ Scent');
      expect(manifest['theme_color'], '#D4AF37');
    });
  });
}
