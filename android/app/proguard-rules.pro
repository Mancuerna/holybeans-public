# Google's QR scanner (ML Kit code scanner) finds its parts by reflection;
# with them renamed or removed the release build fails to start a scan with
# a NullPointerException, while the debug build works.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_code_scanner.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
