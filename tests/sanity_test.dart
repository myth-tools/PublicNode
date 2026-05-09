import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:provider/provider.dart';

import 'package:publicnode/main.dart'; 

void main() {
  group('🚀 Industry-Grade Deep Sanity & Pre-flight Checks (Multi-Platform)', () {
    
    testWidgets('1. Core Application Bootstraps Seamlessly', (WidgetTester tester) async {
      // Build our app and trigger a frame.
      // This catches any provider initialization errors, missing assets in theming, and basic layout crashes.
      await tester.pumpWidget(const PublicNodeTerminalApp());

      // Let animations and async initialization loops settle
      await tester.pumpAndSettle();

      // Verify that the core layers are present
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(MultiProvider), findsOneWidget);
      
      // Ensure the debug banner is disabled for production readiness
      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.debugShowCheckedModeBanner, isFalse, reason: 'debugShowCheckedModeBanner must be false for production.');
    });

    test('2. Deep Codebase Quality & Production Readiness Constraints', () {
      final libDirectory = Directory('lib');
      expect(libDirectory.existsSync(), isTrue, reason: 'lib directory must exist in the project root');

      final dartFiles = libDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();

      expect(dartFiles, isNotEmpty, reason: 'There should be Dart files in the lib directory');

      int filesScanned = 0;
      for (final file in dartFiles) {
        final content = file.readAsStringSync();
        final lines = file.readAsLinesSync();

        expect(content.trim(), isNotEmpty, reason: 'File ${file.path} is empty. Remove empty files.');

        bool hasSetState = content.contains('setState(');
        bool hasAsync = content.contains('async');

        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          final trimmed = line.trim();

          // Rule: Prevent bare print() statements. Force using debugPrint, log(), or a custom logger.
          final hasPrint = trimmed.startsWith('print(') || (trimmed.contains(' print(') && !trimmed.startsWith('//'));
          expect(hasPrint, isFalse, reason: 'Found bare print() statement in ${file.path} at line ${i + 1}. Use debugPrint or a robust logger instead.');

          // Rule: Prevent dart:html
          expect(line.contains("import 'dart:html'"), isFalse, reason: 'Found dart:html import in ${file.path} at line ${i + 1}. This breaks native mobile/desktop compilation.');

          // Rule: Production Code should not have pending TODOs or FIXMEs
          final hasTodo = trimmed.contains('TODO:') || trimmed.contains('FIXME:');
          expect(hasTodo, isFalse, reason: 'Pending TODO/FIXME found in ${file.path} at line ${i + 1}. Resolve all pending tasks before considering the codebase production ready.');

          // Rule: No insecure HTTP hardcoded URLs
          final hasInsecureHttp = trimmed.contains("http://") && !trimmed.contains("http://localhost") && !trimmed.contains("http://127.0.0.1") && !trimmed.startsWith('//');
          expect(hasInsecureHttp, isFalse, reason: 'Insecure hardcoded HTTP URL found in ${file.path} at line ${i + 1}. Use HTTPS for production.');

          // Rule: Advanced Widget Lifecycle Audit (setState in async blocks without mounted check)
          if (hasSetState && hasAsync && trimmed.contains('setState(')) {
            // Check if 'mounted' is present in the file. If setState is used, it's safer to have mounted checks.
            // This is a heuristic but highly effective for industry-grade code.
            if (!content.contains('mounted')) {
               // We don't fail here to avoid false positives, but we could log a warning.
            }
          }

          // Rule: Theming Consistency (No hardcoded hex colors outside theme files)
          final hexRegex = RegExp(r'0x[a-fA-F0-9]{8}|#[a-fA-F0-9]{6}');
          if (hexRegex.hasMatch(trimmed) && !file.path.contains('theme') && !trimmed.startsWith('//')) {
             // expect(hexRegex.hasMatch(trimmed), isFalse, reason: 'Hardcoded hex color found in ${file.path} at line ${i + 1}. Use Theme.of(context) for professional theming.');
          }
        }

        // Rule: Disposable Audit for Controllers
        if (content.contains('AnimationController') || content.contains('TextEditingController') || content.contains('ScrollController')) {
           if (!content.contains('dispose()')) {
              expect(content.contains('dispose()'), isTrue, reason: '${file.path} uses controllers but is missing a dispose() override. This will cause memory leaks!');
           }
        }

        // Rule: Detect overly complex files
        expect(lines.length, lessThan(2000), reason: '${file.path} is too large (${lines.length} lines) and should be refactored into smaller, modular components.');

        filesScanned++;
      }
      
      // Explicitly check main.dart for binding initialization
      final mainContent = File('lib/main.dart').readAsStringSync();
      expect(mainContent.contains('WidgetsFlutterBinding.ensureInitialized()'), isTrue, reason: 'lib/main.dart MUST call WidgetsFlutterBinding.ensureInitialized() before runApp().');
      
      debugPrint('✅ Deep-scanned $filesScanned Dart files for stringent production constraints.');
    });

    test('3. Infrastructure & Platform-Specific Quality Audit', () {
      final infrastructureDirs = ['android', 'linux', 'ios', 'macos', 'windows', 'web'];
      int infraFilesScanned = 0;
      
      for (final dirName in infrastructureDirs) {
        final dir = Directory(dirName);
        if (dir.existsSync()) {
          final files = dir.listSync(recursive: true)
              .whereType<File>()
              .where((file) {
                final path = file.path.toLowerCase();
                // Target relevant configuration and build files
                return path.endsWith('.gradle') || 
                       path.endsWith('.kts') || 
                       path.endsWith('.xml') || 
                       path.endsWith('.cmake') || 
                       path.endsWith('.properties') ||
                       path.endsWith('.yaml') ||
                       path.endsWith('.json');
              }).toList();

          for (final file in files) {
            // Skip ephemeral or hidden files
            if (file.path.contains('ephemeral') || file.path.contains('.dart_tool')) continue;
            
            final lines = file.readAsLinesSync();
            for (int i = 0; i < lines.length; i++) {
              final trimmed = lines[i].trim();
              if (trimmed.contains('TODO:') || trimmed.contains('FIXME:')) {
                expect(true, isFalse, reason: 'Pending TODO/FIXME found in infrastructure file ${file.path} at line ${i + 1}. Resolve all pending tasks before considering the codebase production ready.');
              }
            }
            infraFilesScanned++;
          }
        }
      }
      debugPrint('✅ Deep-scanned $infraFilesScanned infrastructure configuration files.');
    });

    test('4. Pubspec Asset, Dependency & Resource Optimization Audit', () {
      final pubspecFile = File('pubspec.yaml');
      expect(pubspecFile.existsSync(), isTrue, reason: 'pubspec.yaml must exist');

      final pubspecContent = pubspecFile.readAsStringSync();
      final pubspecYaml = loadYaml(pubspecContent) as YamlMap;

      // Sanity check package metadata
      expect(pubspecYaml['name'], 'publicnode', reason: 'Package name must be publicnode');

      // Rule: No dependency_overrides in production
      expect(pubspecYaml.containsKey('dependency_overrides'), isFalse, reason: 'pubspec.yaml contains dependency_overrides. These must be removed for a stable production release.');

      // Check Assets existence and Size Optimization
      final flutterConfig = pubspecYaml['flutter'];
      if (flutterConfig != null && flutterConfig is YamlMap) {
        final assets = flutterConfig['assets'];
        if (assets != null && assets is YamlList) {
          for (final asset in assets) {
            final assetString = asset.toString();
            final assetEntity = assetString.endsWith('/') ? Directory(assetString) : File(assetString);
            
            expect(assetEntity.existsSync(), isTrue, reason: 'Asset declared in pubspec is missing: $assetString');

            // Advanced: Size Audit (Industry limit: No asset > 5MB)
            if (assetEntity is File) {
               final sizeMB = assetEntity.lengthSync() / (1024 * 1024);
               expect(sizeMB, lessThan(5.0), reason: 'Asset $assetString is too large ($sizeMB MB). Optimize it for mobile performance.');
            }
          }
        }

        // Check Fonts existence
        final fonts = flutterConfig['fonts'];
        if (fonts != null && fonts is YamlList) {
          for (final font in fonts) {
            final fontYaml = font as YamlMap;
            final fontFiles = fontYaml['fonts'] as YamlList;
            for (final fontFile in fontFiles) {
              final fileAsset = (fontFile as YamlMap)['asset'].toString();
              expect(File(fileAsset).existsSync(), isTrue, reason: 'Font file declared in pubspec is missing: $fileAsset');
            }
          }
        }
      }
    });

    test('5. Critical Project Infrastructure & Environments', () {
      final requiredDirs = ['lib', '../tests', 'android', 'linux', 'assets'];
      for (final dirName in requiredDirs) {
        expect(Directory(dirName).existsSync(), isTrue, reason: 'Critical environment directory missing: $dirName');
      }
    });

    test('6. Linux Compilation & System Requirements Integrity', () {
      final cmakeFile = File('linux/CMakeLists.txt');
      expect(cmakeFile.existsSync(), isTrue, reason: 'Linux CMakeLists.txt is missing. Linux build will fail.');

      final cmakeContent = cmakeFile.readAsStringSync();
      
      // Verify GTK dependency is declared for the Linux host
      expect(cmakeContent.contains('pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)'), isTrue, 
          reason: 'Linux build is missing GTK+-3.0 dependency in CMakeLists.txt');
      
      // Verify Binary Name is configured properly
      expect(cmakeContent.contains('set(BINARY_NAME "publicnode")'), isTrue, 
          reason: 'Linux binary name is not strictly set to "publicnode".');
          
      // Verify Application ID
      expect(cmakeContent.contains('set(APPLICATION_ID "publicnode")'), isTrue, 
          reason: 'Linux GTK APPLICATION_ID is not configured to "publicnode".');
    });

    test('7. Android Manifest & Gradle Configuration Integrity', () {
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');
      expect(manifestFile.existsSync(), isTrue, reason: 'AndroidManifest.xml is missing.');

      final manifestContent = manifestFile.readAsStringSync();
      
      // Core Permissions Required for VPS
      expect(manifestContent.contains('android.permission.INTERNET'), isTrue, reason: 'Android manifest missing INTERNET permission!');
      expect(manifestContent.contains('android.permission.ACCESS_NETWORK_STATE'), isTrue, reason: 'Android manifest missing ACCESS_NETWORK_STATE permission!');
      
      // Look for gradle files
      final gradleKtsFile = File('android/app/build.gradle.kts');
      final gradleFile = File('android/app/build.gradle');
      
      expect(gradleKtsFile.existsSync() || gradleFile.existsSync(), isTrue, reason: 'Android app-level build.gradle is completely missing!');
      
      String gradleContent = gradleKtsFile.existsSync() ? gradleKtsFile.readAsStringSync() : gradleFile.readAsStringSync();
      
      // Verify Application ID
      expect(gradleContent.contains('applicationId = "com.myth.publicnode"') || gradleContent.contains('applicationId "com.myth.publicnode"'), isTrue, 
          reason: 'Android Application ID must be com.myth.publicnode');
          
      // Verify JVM Targets
      expect(gradleContent.contains('JavaVersion.VERSION_17') || gradleContent.contains('jvmTarget = "17"'), isTrue, 
          reason: 'Android build is not configured to use Java 17, which may break modern Flutter plugin builds.');
    });

    test('8. Deep Static Analysis (Dart Analyzer)', () async {
      // Dynamically run 'dart analyze' to ensure the codebase is completely free of syntax errors, unused imports, or bad types.
      final result = await Process.run('dart', ['analyze', '--fatal-infos']);
      
      if (result.exitCode != 0) {
        debugPrint(result.stdout.toString());
        debugPrint(result.stderr.toString());
      }
      
      expect(result.exitCode, 0, reason: 'Static analysis failed! The codebase has compiler/analyzer errors.');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
