# ONNX Runtime JNI looks up these classes, constructors and members by name.
# The Android AAR has no consumer keep rules. Renaming TensorInfo / NodeInfo
# makes the first native session abort even though debug and JVM tests pass.
-keep class ai.onnxruntime.** { *; }
