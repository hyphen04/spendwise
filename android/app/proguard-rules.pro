# SpendWise R8 / ProGuard keep rules.
#
# Empty by default — R8 with `proguard-android-optimize.txt` is enabled in
# android/app/build.gradle. If a reflectively-loaded plugin breaks at runtime
# after a release build (sqlite3_flutter_libs, drift, flutter_markdown, pdf,
# etc.), add a `-keep` rule for it here rather than disabling minify.
#
# Flutter's own rules are injected automatically by the Flutter Gradle plugin
# (flutter_project rules + io.flutter.* keeps), so app code shrunken by R8 is
# safe. Plugin native libs (.so) are not affected by R8; only Java/Kotlin
# bytecode is. Most Flutter plugins are fully tree-shaken without extra rules.