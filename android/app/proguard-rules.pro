# R8/ProGuard keep rules for release builds.
#
# Flutter enables R8 (shrinking + obfuscation) for release by default. Without
# these rules R8 strips/obfuscates Google ML Kit classes that mobile_scanner
# loads reflectively, so the scanner crashes on start with a NullPointerException
# in dev.steenbakker.mobile_scanner and the camera preview stays black (works in
# debug, where R8 doesn't run). Keep ML Kit (barcode model) intact.

# Google ML Kit (barcode scanning backs mobile_scanner).
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**

# mobile_scanner plugin itself.
-keep class dev.steenbakker.mobile_scanner.** { *; }
