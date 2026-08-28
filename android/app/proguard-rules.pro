# flutter_webrtc relies on native WebRTC classes and MethodChannel DTOs that
# must stay intact in minified release builds.
-keep class com.cloudwebrtc.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-keep class org.jni_zero.** { *; }
