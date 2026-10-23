# flutter_local_notifications 18 uses Gson to persist scheduled notifications.
# R8 full mode must retain TypeToken subclasses and their generic signatures;
# otherwise even reloading a saved [] throws "TypeToken must be created with a
# type argument" during cancel/pending/schedule operations in release builds.
-keepattributes Signature
-keepattributes *Annotation*
-keep,allowobfuscation,allowshrinking class com.google.gson.reflect.TypeToken
-keep,allowobfuscation,allowshrinking class * extends com.google.gson.reflect.TypeToken

# Gson's reflective adapters and annotated fields (plugin-recommended rules).
-keep class * extends com.google.gson.TypeAdapter
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer
-keepclassmembers,allowobfuscation class * {
    @com.google.gson.annotations.SerializedName <fields>;
}
