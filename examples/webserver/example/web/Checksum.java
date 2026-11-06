package example.web;

/** Bound to libwebchecksum through the BendJVM native plugin bridge (not JNI). */
final class Checksum {
    static {
        System.loadLibrary("webchecksum");
    }

    private Checksum() {
    }

    static native int fnv1a(byte[] data);
}
