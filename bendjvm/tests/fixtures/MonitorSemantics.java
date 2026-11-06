import java.util.ArrayList;
import java.util.List;

// Monitors, synchronized methods/blocks and wait/notify (plan 05).
public class MonitorSemantics {
    static int counter;
    static final List<String> log = new ArrayList<String>();

    static synchronized void increment() {
        counter++;
    }

    static synchronized boolean staticHoldsClassLock() {
        return Thread.holdsLock(MonitorSemantics.class);
    }

    int instanceCounter;

    synchronized void instanceIncrement() {
        instanceCounter++;
    }

    synchronized boolean instanceHolds() {
        return Thread.holdsLock(this) && !Thread.holdsLock(MonitorSemantics.class);
    }

    synchronized void failInside() {
        throw new IllegalStateException("inside synchronized");
    }

    static void say(String text) {
        synchronized (log) {
            log.add(text);
        }
    }

    // A bounded queue guarded by wait/notifyAll.
    static class Queue {
        private final int[] items = new int[2];
        private int count;
        private int head;

        synchronized void put(int value) throws InterruptedException {
            while (count == items.length) {
                wait();
            }
            items[(head + count) % items.length] = value;
            count++;
            notifyAll();
        }

        synchronized int take() throws InterruptedException {
            while (count == 0) {
                wait();
            }
            int value = items[head];
            head = (head + 1) % items.length;
            count--;
            notifyAll();
            return value;
        }
    }

    public static void main(String[] args) throws Exception {
        // Contended increments lose nothing under synchronization.
        Thread[] threads = new Thread[4];
        final MonitorSemantics shared = new MonitorSemantics();
        for (int i = 0; i < threads.length; i++) {
            threads[i] = new Thread(new Runnable() {
                public void run() {
                    for (int j = 0; j < 500; j++) {
                        increment();
                        shared.instanceIncrement();
                    }
                }
            });
            threads[i].start();
        }
        for (Thread thread : threads) {
            thread.join();
        }
        System.out.println("static counter: " + counter + " instance counter: " + shared.instanceCounter);

        // Lock identities: static methods lock the Class, instance methods the receiver.
        System.out.println("static holds class lock: " + staticHoldsClassLock());
        System.out.println("instance holds only receiver: " + shared.instanceHolds());
        System.out.println("holds outside: " + Thread.holdsLock(shared));

        // Exceptions release the implicit lock.
        try {
            shared.failInside();
        } catch (IllegalStateException expected) {
            System.out.println("after throw holds: " + Thread.holdsLock(shared));
        }
        Thread other = new Thread(new Runnable() {
            public void run() {
                shared.instanceIncrement();
            }
        });
        other.start();
        other.join();
        System.out.println("other thread entered: " + shared.instanceCounter);

        // Recursive wait restores the full recursion depth.
        final Object monitor = new Object();
        final boolean[] go = new boolean[1];
        Thread waiter = new Thread(new Runnable() {
            public void run() {
                synchronized (monitor) {
                    synchronized (monitor) {
                        say("waiter waiting");
                        while (!go[0]) {
                            try {
                                monitor.wait();
                            } catch (InterruptedException e) {
                                say("unexpected interrupt");
                            }
                        }
                        say("waiter woke, holds " + Thread.holdsLock(monitor));
                    }
                    say("inner released, still holds " + Thread.holdsLock(monitor));
                }
                say("outer released, holds " + Thread.holdsLock(monitor));
            }
        }, "waiter");
        waiter.start();
        while (waiter.getState() != Thread.State.WAITING) {
            Thread.yield();
        }
        synchronized (monitor) {
            go[0] = true;
            monitor.notify();
            // notify does not hand the monitor over: the waiter is still blocked.
            say("notifier still owns: " + Thread.holdsLock(monitor));
            for (int i = 0; i < 2000; i++) {
                Thread.yield();
            }
            say("notifier leaving");
        }
        waiter.join();
        System.out.println("log: " + log);
        log.clear();

        // Ownership checks.
        try {
            monitor.wait();
        } catch (IllegalMonitorStateException expected) {
            System.out.println("wait without lock: " + expected.getClass().getName());
        }
        try {
            monitor.notify();
        } catch (IllegalMonitorStateException expected) {
            System.out.println("notify without lock: " + expected.getClass().getName());
        }
        try {
            Object nothing = null;
            synchronized (nothing) {
                System.out.println("unreachable");
            }
        } catch (NullPointerException expected) {
            System.out.println("synchronized null: " + expected.getClass().getName());
        }
        try {
            Thread.holdsLock(null);
        } catch (NullPointerException expected) {
            System.out.println("holdsLock null: " + expected.getClass().getName());
        }

        // A timed wait returns after its timeout and owns the monitor again.
        synchronized (monitor) {
            long before = System.nanoTime();
            monitor.wait(30);
            long waited = System.nanoTime() - before;
            System.out.println("timed wait returned, holds " + Thread.holdsLock(monitor) + ", waited >= 25ms " + (waited >= 25000000L));
        }

        // Interrupting a waiter: it reacquires the monitor before throwing.
        final Thread interrupted = new Thread(new Runnable() {
            public void run() {
                synchronized (monitor) {
                    try {
                        monitor.wait();
                        say("no interrupt");
                    } catch (InterruptedException expected) {
                        say("interrupted wait holds " + Thread.holdsLock(monitor) + " flag " + Thread.currentThread().isInterrupted());
                    }
                }
            }
        });
        interrupted.start();
        while (interrupted.getState() != Thread.State.WAITING) {
            Thread.yield();
        }
        interrupted.interrupt();
        interrupted.join();
        System.out.println("log: " + log);

        // Producer/consumer through the wait/notify queue.
        final Queue queue = new Queue();
        final int[] sum = new int[1];
        Thread consumer = new Thread(new Runnable() {
            public void run() {
                try {
                    for (int i = 0; i < 20; i++) {
                        sum[0] += queue.take();
                    }
                } catch (InterruptedException e) {
                    sum[0] = -1;
                }
            }
        });
        consumer.start();
        for (int i = 1; i <= 20; i++) {
            queue.put(i);
        }
        consumer.join();
        System.out.println("consumed sum: " + sum[0]);

        // wait argument checks.
        synchronized (monitor) {
            try {
                monitor.wait(-1);
            } catch (IllegalArgumentException expected) {
                System.out.println("negative wait: " + expected.getMessage());
            }
            try {
                monitor.wait(0, 1000000);
            } catch (IllegalArgumentException expected) {
                System.out.println("bad nanos: " + expected.getMessage());
            }
        }
    }
}
