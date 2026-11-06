import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.invoke.MutableCallSite;
import java.lang.invoke.VolatileCallSite;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;

// Volatile visibility/atomicity and cross-thread class initialization (plan 05).
public class VolatilePublication {
    static int data;
    static volatile boolean ready;
    static volatile long wide;
    static volatile double wideDouble;
    static volatile boolean stop;
    volatile String name = "initial";

    static class Slow {
        static final int VALUE;
        static int initializations;

        static {
            initializations++;
            int total = 0;
            for (int i = 0; i < 20000; i++) {
                total += i % 7;
            }
            VALUE = total;
        }
    }

    static String first() {
        return "first";
    }

    static String second() {
        return "second";
    }

    static volatile boolean retargeted;

    public static void main(String[] args) throws Throwable {
        // Message passing: data written before the volatile flag is visible after it.
        Thread writer = new Thread(new Runnable() {
            public void run() {
                data = 1234;
                ready = true;
            }
        });
        writer.start();
        while (!ready) {
            // busy wait: requires preemption, no yield
        }
        System.out.println("published data: " + data);
        writer.join();

        // Volatile long/double values never tear.
        Thread flipper = new Thread(new Runnable() {
            public void run() {
                for (int i = 0; i < 4000 && !stop; i++) {
                    wide = (i % 2 == 0) ? -1L : 0x0000000100000001L;
                    wideDouble = (i % 2 == 0) ? -0.5 : 1.0e300;
                }
            }
        });
        flipper.start();
        boolean torn = false;
        for (int i = 0; i < 3000; i++) {
            long seen = wide;
            double seenDouble = wideDouble;
            if (seen != 0L && seen != -1L && seen != 0x0000000100000001L) {
                torn = true;
            }
            if (seenDouble != 0.0 && seenDouble != -0.5 && seenDouble != 1.0e300) {
                torn = true;
            }
        }
        stop = true;
        flipper.join();
        System.out.println("torn: " + torn);

        // Unsynchronized increments are not atomic; only the bound is guaranteed.
        final int[] racy = new int[1];
        Thread[] incrementers = new Thread[3];
        for (int t = 0; t < incrementers.length; t++) {
            incrementers[t] = new Thread(new Runnable() {
                public void run() {
                    for (int i = 0; i < 1000; i++) {
                        racy[0]++;
                    }
                }
            });
            incrementers[t].start();
        }
        for (Thread thread : incrementers) {
            thread.join();
        }
        System.out.println("racy total within bound: " + (racy[0] > 0 && racy[0] <= 3000));

        // Start and join publish ordinary writes.
        final int[] fromWorker = new int[1];
        final int before = 77;
        Thread publisher = new Thread(new Runnable() {
            public void run() {
                fromWorker[0] = before + 1;
            }
        });
        publisher.start();
        publisher.join();
        System.out.println("joined write: " + fromWorker[0]);

        // Competing class initialization runs <clinit> exactly once.
        final int[] seen = new int[2];
        Thread first = new Thread(new Runnable() {
            public void run() {
                seen[0] = Slow.VALUE;
            }
        });
        Thread second = new Thread(new Runnable() {
            public void run() {
                seen[1] = Slow.VALUE;
            }
        });
        first.start();
        second.start();
        first.join();
        second.join();
        System.out.println("class init: " + seen[0] + " " + seen[1] + " runs " + Slow.initializations);

        // Volatile fields through reflection.
        Field flag = VolatilePublication.class.getDeclaredField("ready");
        System.out.println("ready is volatile: " + Modifier.isVolatile(flag.getModifiers()));
        Field instance = VolatilePublication.class.getDeclaredField("name");
        VolatilePublication target = new VolatilePublication();
        instance.set(target, "reflected");
        System.out.println("reflective volatile write: " + target.name);
        Field wideField = VolatilePublication.class.getDeclaredField("wide");
        wideField.setLong(null, Long.MIN_VALUE);
        System.out.println("reflective volatile long: " + wide);

        // Call site targets published by one thread are seen by another.
        MethodType type = MethodType.methodType(String.class);
        MethodHandle one = MethodHandles.lookup().findStatic(VolatilePublication.class, "first", type);
        final MethodHandle two = MethodHandles.lookup().findStatic(VolatilePublication.class, "second", type);
        final MutableCallSite mutable = new MutableCallSite(one);
        final VolatileCallSite volatileSite = new VolatileCallSite(one);
        MethodHandle mutableInvoker = mutable.dynamicInvoker();
        MethodHandle volatileInvoker = volatileSite.dynamicInvoker();
        Thread retarget = new Thread(new Runnable() {
            public void run() {
                mutable.setTarget(two);
                MutableCallSite.syncAll(new MutableCallSite[] {mutable});
                volatileSite.setTarget(two);
                retargeted = true;
            }
        });
        String initial = (String) volatileInvoker.invokeExact();
        retarget.start();
        while (!retargeted) {
            // spin until the other thread publishes
        }
        System.out.println("call sites: " + initial + " -> " + (String) mutableInvoker.invokeExact() + " " + (String) volatileInvoker.invokeExact());
        retarget.join();
    }
}
