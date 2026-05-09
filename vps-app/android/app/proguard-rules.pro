# Flutter Industrial Hardening - ProGuard Rules
# (c) 2026 PublicNode

# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flutter Secure Storage - CRITICAL: Prevent credential loss due to obfuscation
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep interface com.it_nomads.fluttersecurestorage.** { *; }

# Shared Preferences (often used as fallback by plugins)
-keep class android.content.SharedPreferences { *; }

# Data Serialization (YAML/JSON)
-keep class org.yaml.snakeyaml.** { *; }
-dontwarn org.yaml.snakeyaml.**

# Network Stack
-keep class com.google.gson.** { *; }
-keep class com.squareup.okhttp3.** { *; }
-dontwarn com.squareup.okhttp3.**

# SSH Core (If any native components are used)
-keep class com.jcraft.jsch.** { *; }

# Prevent shrinking of important lifecycle methods
-keepclassmembers class * extends android.app.Activity {
   public void *(android.view.View);
}

# Standard robustness: keep line numbers for better crash reports
-keepattributes SourceFile,LineNumberTable

# Play Core (referenced by Flutter embedding but often not present)
-dontwarn com.google.android.play.core.**

# Other common plugin dependencies
-dontwarn com.google.common.**
-dontwarn org.checkerframework.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
