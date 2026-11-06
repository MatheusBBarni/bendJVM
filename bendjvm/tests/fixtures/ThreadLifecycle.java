import java.util.ArrayList;
import java.util.List;

// Thread lifecycle, interruption, join and uncaught-exception handling (plan 05).
// Every cross-thread step uses an explicit rendezvous; output is deterministic.
public class ThreadLifecycle {
    static final Object lock = new Object();
    static volatile boolean started;
    static volatile boolean release;
    static final List<String> events = new ArrayList<String>();

    static void record(String event) {
        synchronized (events) {
            events.add(event);
        }
    }

    static class Worker extends Thread {
        Worker(String name) {
            super(name);
        }

        public void run() {
            record("run in " + Thread.currentThread().getName());
        }
    }

    public static void main(String[] args) throws Exception {
        Thread main = Thread.currentThread();
        System.out.println("main name: " + main.getName());
        System.out.println("main is current: " + (main == Thread.currentThread()));
        System.out.println("main alive: " + main.isAlive() + " daemon: " + main.isDaemon());
        System.out.println("main state: " + main.getState());

        // run() is an ordinary call on the caller's thread; start() runs on the new one.
        Worker worker = new Worker("worker-1");
        System.out.println("new state: " + worker.getState() + " alive: " + worker.isAlive());
        worker.run();
        worker.start();
        worker.join();
        System.out.println("joined state: " + worker.getState() + " alive: " + worker.isAlive());
        System.out.println("events: " + events);
        try {
            worker.start();
        } catch (IllegalThreadStateException expected) {
            System.out.println("second start: " + expected.getClass().getName());
        }

        // A Runnable target and default names.
        final int[] box = new int[1];
        Thread runnable = new Thread(new Runnable() {
            public void run() {
                box[0] = 42;
            }
        });
        System.out.println("default name prefix: " + runnable.getName().startsWith("Thread-"));
        runnable.start();
        runnable.join();
        System.out.println("runnable wrote: " + box[0]);

        // Joining a thread that never started returns at once.
        new Thread("never").join();
        System.out.println("joined unstarted thread");

        // Daemon status is inherited and fixed once the thread is alive.
        Thread daemonParent = new Thread(new Runnable() {
            public void run() {
                Thread child = new Thread("child");
                record("child daemon: " + child.isDaemon());
            }
        }, "parent");
        daemonParent.setDaemon(true);
        daemonParent.start();
        daemonParent.join();
        System.out.println("events: " + events);

        // Interrupting a sleeping thread throws InterruptedException and clears the flag.
        final Thread sleeper = new Thread(new Runnable() {
            public void run() {
                started = true;
                try {
                    Thread.sleep(60000);
                    record("sleep finished");
                } catch (InterruptedException expected) {
                    record("sleep interrupted, flag=" + Thread.currentThread().isInterrupted());
                }
            }
        }, "sleeper");
        sleeper.start();
        while (!started) {
            // spin: the scheduler must preempt this loop for the sleeper to run
        }
        while (sleeper.getState() != Thread.State.TIMED_WAITING) {
            Thread.yield();
        }
        System.out.println("sleeper state: " + sleeper.getState());
        sleeper.interrupt();
        sleeper.join();
        System.out.println("events: " + events);

        // Flags: interrupted() clears, isInterrupted() does not.
        main.interrupt();
        System.out.println("isInterrupted: " + main.isInterrupted() + " " + main.isInterrupted());
        System.out.println("interrupted: " + Thread.interrupted() + " " + Thread.interrupted());
        main.interrupt();
        try {
            Thread.sleep(10);
            System.out.println("slept despite interrupt");
        } catch (InterruptedException expected) {
            System.out.println("pending interrupt: " + expected.getMessage() + " flag=" + main.isInterrupted());
        }

        // A timed join returns while the target is still alive.
        started = false;
        Thread blocker = new Thread(new Runnable() {
            public void run() {
                synchronized (lock) {
                    started = true;
                    while (!release) {
                        try {
                            lock.wait();
                        } catch (InterruptedException e) {
                            return;
                        }
                    }
                }
            }
        }, "blocker");
        blocker.start();
        while (!started) {
            Thread.yield();
        }
        blocker.join(20);
        System.out.println("after timed join alive: " + blocker.isAlive() + " state: " + blocker.getState());
        synchronized (lock) {
            release = true;
            lock.notifyAll();
        }
        blocker.join();
        System.out.println("after join alive: " + blocker.isAlive());

        // Argument validation.
        try {
            Thread.sleep(-1);
        } catch (IllegalArgumentException expected) {
            System.out.println("negative sleep: " + expected.getMessage());
        }
        try {
            blocker.join(-5);
        } catch (IllegalArgumentException expected) {
            System.out.println("negative join: " + expected.getMessage());
        }
        try {
            worker.setDaemon(true);
            System.out.println("setDaemon after termination allowed: " + worker.isDaemon());
        } catch (IllegalThreadStateException unexpected) {
            System.out.println("setDaemon rejected");
        }

        // Uncaught exceptions end only their own thread and reach the handlers.
        Thread failing = new Thread(new Runnable() {
            public void run() {
                throw new IllegalStateException("boom");
            }
        }, "failing");
        failing.setUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            public void uncaughtException(Thread t, Throwable e) {
                record("handler saw " + e.getMessage() + " in " + t.getName());
            }
        });
        failing.start();
        failing.join();
        Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            public void uncaughtException(Thread t, Throwable e) {
                record("default handler saw " + e.getClass().getName() + " in " + t.getName());
            }
        });
        Thread failingDefault = new Thread(new Runnable() {
            public void run() {
                throw new UnsupportedOperationException("nope");
            }
        }, "failing-default");
        failingDefault.start();
        failingDefault.join();
        System.out.println("handler is default: " + (failingDefault.getUncaughtExceptionHandler() != null));
        System.out.println("events: " + events);
        System.out.println("main still alive: " + main.isAlive());
    }
}
