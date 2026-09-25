# =============================================================================
# Fadhkur (فذكر) — Production ProGuard & R8 Optimization Rules
# =============================================================================

# --- Android Architecture & Core ---
-keepattributes SourceFile,LineNumberTable,*Annotation*,Signature,InnerClasses,EnclosingMethod

# --- Fadhkur Domain Models ---
-keep class app.fadhkur.model.** { *; }
-keepclassmembers class app.fadhkur.model.** { *; }

# --- Firebase Services & Common ---
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keepattributes *Annotation*
-keepclassmembers class * {
    @com.google.firebase.firestore.PropertyName <fields>;
    @com.google.firebase.firestore.PropertyName <methods>;
}

# --- Kotlin Coroutines & StateFlow ---
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-keepclassmembernames class kotlinx.coroutines.** {
    volatile <fields>;
}
-dontwarn kotlinx.coroutines.**

# --- Jetpack Compose ---
-keep class androidx.compose.runtime.** { *; }
-dontwarn androidx.compose.**

# --- Moshi & JSON Parsing ---
-keepclasseswithmembers class * {
    @com.squareup.moshi.* <methods>;
}
-keep @com.squareup.moshi.JsonQualifier interface *
-keepclassmembers class * {
    @com.squareup.moshi.Json <fields>;
}

# --- OkHttp & Retrofit ---
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn retrofit2.**
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
