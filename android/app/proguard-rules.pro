# Kute release R8 rules.
#
# R8 shrinks and obfuscates the release build. Every library that needs
# names at runtime either ships its own consumer rules inside its AAR
# (AndroidX, Firebase, Play services, ML Kit, AppsFlyer, PostHog, Crisp,
# Tink, OkHttp, Flutter plugins ...) or is listed here. Nothing else is
# kept, so Play's DEX obfuscation check passes.
#
# Through 2.1.x this file had a blanket `-keep class * { public private *; }`
# plus `-ignorewarnings`, which kept every class and member name in the
# app. Play Console flagged "Obfuscation (7%)". Do not bring it back: add
# a targeted rule for the class that actually needs its name instead.

#--------------------------------------
# Crash reports
#--------------------------------------
# Crashlytics de-obfuscates with the mapping file the Crashlytics Gradle
# plugin uploads; it still needs file names and line numbers in frames.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
# Exception class names stay readable (shrinking still applies).
# Required: OnchainPlugin.transactionFailureCode() maps BDK errors to send
# categories by Throwable.javaClass.simpleName (e.g. "InsufficientFunds"),
# and MainActivity reports e::class.java.simpleName back to Dart.
-keepnames class * extends java.lang.Throwable

#--------------------------------------
# Reflection metadata
#--------------------------------------
# Generic signatures, inner-class tables and annotations are read through
# reflection by JNA (Structure.FieldOrder), Gson/kotlinx models inside the
# SDKs and Kotlin coroutines.
-keepattributes Signature,InnerClasses,EnclosingMethod,Exceptions
-keepattributes RuntimeVisibleAnnotations,RuntimeVisibleParameterAnnotations,AnnotationDefault

# AppsFlyer's consumer rules keep the kotlin.Metadata class but not its
# members, which leaves R8 unable to read (and rewrite) Kotlin metadata on
# kept classes. Keep the annotation's elements so metadata stays valid.
-keep class kotlin.Metadata { *; }

#--------------------------------------
# JNI / native methods
#--------------------------------------
# A native method binds to its C symbol by class + method name.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

#--------------------------------------
# JNA + BDK (org.bitcoindevkit, UniFFI bindings used by OnchainPlugin)
#--------------------------------------
# bdk-android and JNA ship no consumer rules. UniFFI binds UniffiLib's
# native methods with Native.register (direct mapping, by method name),
# JNA reads Structure fields by name (@FieldOrder) and calls Callback
# implementations through reflection, and libjnidispatch calls back into
# com.sun.jna classes by name.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class * extends com.sun.jna.** { *; }
-keep interface * extends com.sun.jna.** { *; }
-dontwarn java.awt.**
-dontwarn com.sun.jna.**
# UniffiLib / IntegrityCheckingUniffiLib: the classes Native.register
# binds; their static INSTANCE and native method names must stay.
-keep class org.bitcoindevkit.UniffiLib { *; }
-keep class org.bitcoindevkit.IntegrityCheckingUniffiLib { *; }

#--------------------------------------
# package:jni (path_provider_android via jnigen)
#--------------------------------------
# The jni plugin keeps its own com.github.dart_lang.jni.** classes; its
# Dart core bindings also look up these Kotlin stdlib classes by name.
-keep class kotlin.Unit { *; }
-keep class kotlin.Result { *; }
-keep class kotlin.Result$Failure { *; }
-keep interface kotlin.coroutines.Continuation { *; }

#--------------------------------------
# Flutter
#--------------------------------------
# The embedding ships consumer rules; GeneratedPluginRegistrant references
# each plugin class directly. MainActivity is named in the manifest.
-dontwarn io.flutter.embedding.**
# Play Core deferred components are referenced by the embedding but not
# shipped (no deferred components in Kute).
-dontwarn com.google.android.play.core.**

#--------------------------------------
# flutter_local_notifications
#--------------------------------------
# The plugin ships no consumer rules. It stores scheduled notifications
# as Gson JSON in SharedPreferences (field names = JSON keys) and its
# RuntimeTypeAdapterFactory labels subtypes with Class.getSimpleName();
# the boot receiver reads them back. Renaming either would break data
# written by an earlier build.
-keep class com.dexterous.flutterlocalnotifications.** { *; }

#--------------------------------------
# PostHog Flutter plugin
#--------------------------------------
# PosthogFlutterPlugin.firebaseProjectId() looks these up reflectively for
# push-subscription attribution.
-keepnames class com.google.firebase.FirebaseApp
-keepclassmembers class com.google.firebase.FirebaseApp {
    public static com.google.firebase.FirebaseApp getInstance();
    public com.google.firebase.FirebaseOptions getOptions();
}
-keepclassmembers class com.google.firebase.FirebaseOptions {
    public java.lang.String getProjectId();
}

#--------------------------------------
# WebView JavaScript channels
#--------------------------------------
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

#--------------------------------------
# Platform conventions
#--------------------------------------
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
