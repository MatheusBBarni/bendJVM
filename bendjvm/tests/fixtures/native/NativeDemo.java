// Exercises the BendJVM native plugin bridge against libbendjvmdemo (demo_plugin.c).
// This is not a JNI program: it only runs on BendJVM with
// --native-library bendjvmdemo=/path/to/libbendjvmdemo.<so|dylib>.
public class NativeDemo {
    static {
        System.loadLibrary("bendjvmdemo");
    }

    static native int add(int a, int b);

    static native long mulWide(long a, long b);

    static native double scale(double a, double b);

    static native void fill(byte[] buffer, int start);

    static native int sum(int[] values);

    static native String greet(String name);

    static native long openCounter(long start);

    static native long increment(long counter);

    static native void closeCounter(long counter);

    static native void fail(String message);

    static native void raiseUnregistered();

    static native int sleepMillis(int millis);

    static synchronized native int lockedAdd(int a, int b);

    static native void crash();

    static native int unbound(int x);

    static volatile boolean slowDone;
    static volatile int progress;

    public static void main(String[] args) throws Exception {
        System.out.println("add: " + add(40, 2) + " " + add(Integer.MAX_VALUE, 1));
        System.out.println("mulWide: " + mulWide(3000000000L, 7L) + " " + mulWide(-1L, Long.MIN_VALUE));
        System.out.println("scale: " + scale(1.5, -2.25));
        byte[] buffer = new byte[5];
        fill(buffer, 126);
        StringBuilder bytes = new StringBuilder();
        for (byte b : buffer) {
            bytes.append(b).append(' ');
        }
        System.out.println("fill: " + bytes.toString().trim());
        System.out.println("sum: " + sum(new int[] {1, 2, 3, 400000}));
        System.out.println("greet: " + greet("Bend ☺"));

        long counter = openCounter(41);
        System.out.println("counter: " + increment(counter) + " " + increment(counter));
        closeCounter(counter);
        try {
            increment(counter);
        } catch (IllegalArgumentException expected) {
            System.out.println("closed handle: " + expected.getMessage());
        }
        try {
            increment(12345L);
        } catch (IllegalArgumentException expected) {
            System.out.println("forged handle: " + expected.getMessage());
        }
        try {
            fail("plugin said no");
        } catch (IllegalStateException expected) {
            System.out.println("mapped failure: " + expected.getMessage());
        }
        try {
            raiseUnregistered();
        } catch (IllegalStateException expected) {
            System.out.println("unregistered failure: " + expected.getClass().getName());
        }
        try {
            fill(null, 0);
        } catch (NullPointerException expected) {
            System.out.println("null buffer: " + expected.getMessage());
        }
        try {
            unbound(1);
        } catch (UnsatisfiedLinkError expected) {
            System.out.println("unbound: " + expected.getMessage());
        }
        try {
            System.load("/definitely/not/allowed/libx.so");
        } catch (UnsatisfiedLinkError expected) {
            System.out.println("disallowed load: " + expected.getClass().getName());
        }
        try {
            System.loadLibrary("unknownlib");
        } catch (UnsatisfiedLinkError expected) {
            System.out.println("unknown library: " + expected.getMessage());
        }

        // A slow native call parks only its thread; this thread keeps running.
        Thread slow = new Thread(new Runnable() {
            public void run() {
                sleepMillis(300);
                slowDone = true;
            }
        });
        slow.start();
        while (!slowDone) {
            progress++;
        }
        slow.join();
        System.out.println("progress during slow call: " + (progress > 0));

        // A synchronized native holds its class monitor for the whole call.
        System.out.println("locked: " + lockedAdd(1, 2) + " holds after: " + Thread.holdsLock(NativeDemo.class));

        // A crash ends only the helper process; Java keeps running.
        try {
            crash();
        } catch (InternalError expected) {
            System.out.println("crash contained: " + expected.getMessage());
        }
        try {
            add(1, 1);
        } catch (UnsatisfiedLinkError expected) {
            System.out.println("after crash: " + expected.getClass().getName());
        }
        System.out.println("done");
    }
}
