# NewPipeExtractor's JavaScript interpreter uses reflective class access.
-keep class org.mozilla.javascript.** { *; }
-keep class org.mozilla.classfile.ClassFileWriter
-dontwarn org.mozilla.javascript.tools.**
# Desktop-only Rhino integrations are not used by NewPipe's interpreted mode.
-dontwarn javax.script.**
-dontwarn jdk.dynalink.**
-dontwarn java.beans.BeanDescriptor
-dontwarn java.beans.BeanInfo
-dontwarn java.beans.IntrospectionException
-dontwarn java.beans.Introspector
-dontwarn java.beans.PropertyDescriptor
-keep class org.schabi.newpipe.extractor.timeago.patterns.** { *; }
# Protobuf decoders access generated field names reflectively.
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite {
    <fields>;
}
