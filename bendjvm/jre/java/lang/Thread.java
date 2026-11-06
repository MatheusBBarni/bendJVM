package java.lang;

/**
 * Java threads multiplexed on the Bend scheduler.
 *
 * Every lifecycle transition is a native bound to a Bend intrinsic: the scheduler
 * owns the thread record (frames, wait reason, interrupt flag, deadline) and this
 * class only keeps the Java-visible metadata (name, daemon flag, handlers).
 */
public class Thread implements Runnable {
    public static final int MIN_PRIORITY = 1;
    public static final int NORM_PRIORITY = 5;
    public static final int MAX_PRIORITY = 10;

    public enum State { NEW, RUNNABLE, BLOCKED, WAITING, TIMED_WAITING, TERMINATED }

    public interface UncaughtExceptionHandler {
        void uncaughtException(Thread t, Throwable e);
    }

    private static int threadInitNumber;
    private static long threadSeqNumber = 1;
    private static volatile UncaughtExceptionHandler defaultUncaughtExceptionHandler;

    private volatile String name;
    private final Runnable target;
    // Null once the thread has terminated (JDK 8 Thread.exit).
    private volatile ThreadGroup group;
    private final long tid;
    private int priority;
    private boolean daemon;
    private boolean started;
    // interrupt() on a thread that has not started yet; handed to the scheduler by start().
    private boolean pendingInterrupt;
    private volatile UncaughtExceptionHandler uncaughtExceptionHandler;

    public Thread() {
        this(null, null, nextThreadName(), 0);
    }

    public Thread(Runnable target) {
        this(null, target, nextThreadName(), 0);
    }

    public Thread(String name) {
        this(null, null, name, 0);
    }

    public Thread(Runnable target, String name) {
        this(null, target, name, 0);
    }

    public Thread(ThreadGroup group, Runnable target) {
        this(group, target, nextThreadName(), 0);
    }

    public Thread(ThreadGroup group, String name) {
        this(group, null, name, 0);
    }

    public Thread(ThreadGroup group, Runnable target, String name) {
        this(group, target, name, 0);
    }

    // The stack size is a hint the JDK may ignore; BendJVM stacks are bounded by fuel.
    public Thread(ThreadGroup group, Runnable target, String name, long stackSize) {
        this(group, target, name, 0);
    }

    private Thread(ThreadGroup group, Runnable target, String name, int unused) {
        if (name == null) {
            throw new NullPointerException("name cannot be null");
        }
        Thread parent = currentThread();
        ThreadGroup g = group != null ? group : parent.getThreadGroup();
        g.checkStart();
        this.name = name;
        this.target = target;
        this.group = g;
        this.daemon = parent.daemon;
        this.priority = Math.min(parent.priority, g.getMaxPriority());
        this.tid = nextThreadID();
    }

    // The main thread's object, created the first time the main thread asks for it.
    private Thread(ThreadGroup group) {
        this.name = "main";
        this.target = null;
        this.group = group;
        this.tid = 1;
        this.priority = NORM_PRIORITY;
        this.started = true;
    }

    private static synchronized String nextThreadName() {
        return "Thread-" + threadInitNumber++;
    }

    private static synchronized long nextThreadID() {
        return ++threadSeqNumber;
    }

    public static Thread currentThread() {
        Thread current = current0();
        if (current == null) {
            // Only the main thread starts without an object; workers get theirs from start().
            ThreadGroup main = ThreadGroup.mainGroup();
            current = new Thread(main);
            main.add(current);
            attachMain0(current);
        }
        return current;
    }

    public synchronized void start() {
        if (started) {
            throw new IllegalThreadStateException();
        }
        group.add(this);
        started = true;
        start0(daemon, pendingInterrupt, priority);
    }

    public void run() {
        if (target != null) {
            target.run();
        }
    }

    // The first frame of every started thread. The thread terminates when it returns.
    private void bendRun() {
        try {
            run();
        } catch (Throwable e) {
            dispatchUncaughtException(e);
        } finally {
            ThreadGroup g = group;
            if (g != null) {
                g.threadTerminated(this);
            }
            group = null;
        }
    }

    private void dispatchUncaughtException(Throwable e) {
        try {
            getUncaughtExceptionHandler().uncaughtException(this, e);
        } catch (Throwable ignored) {
            System.err.print("\nException: " + ignored.getClass().getName()
                + " thrown from the UncaughtExceptionHandler in thread \"" + getName() + "\"\n");
        }
    }

    // Called by the VM when main() ends with an exception, as the JDK launcher
    // does: the thread's handler, else its group (the default handler, or the
    // "Exception in thread "main"" report). True once dispatched.
    private static boolean mainUncaught(Throwable e) {
        Thread main = currentThread();
        main.dispatchUncaughtException(e);
        return true;
    }

    public final boolean isAlive() {
        return started && alive0();
    }

    public State getState() {
        if (!started) {
            return State.NEW;
        }
        switch (state0()) {
            case 1:
                return State.RUNNABLE;
            case 2:
                return State.BLOCKED;
            case 3:
                return State.WAITING;
            case 4:
                return State.TIMED_WAITING;
            default:
                return State.TERMINATED;
        }
    }

    public final ThreadGroup getThreadGroup() {
        return group;
    }

    public static int activeCount() {
        return currentThread().getThreadGroup().activeCount();
    }

    public static int enumerate(Thread[] tarray) {
        return currentThread().getThreadGroup().enumerate(tarray);
    }

    public final void checkAccess() {
    }

    public long getId() {
        return tid;
    }

    public final String getName() {
        return name;
    }

    public final synchronized void setName(String name) {
        if (name == null) {
            throw new NullPointerException("name cannot be null");
        }
        this.name = name;
    }

    public final boolean isDaemon() {
        return daemon;
    }

    public final void setDaemon(boolean on) {
        if (isAlive()) {
            throw new IllegalThreadStateException();
        }
        daemon = on;
    }

    // Priorities weight the scheduler: each turn lasts quantum * priority / 5 instructions.
    public final int getPriority() {
        return priority;
    }

    public final void setPriority(int newPriority) {
        if (newPriority > MAX_PRIORITY || newPriority < MIN_PRIORITY) {
            throw new IllegalArgumentException();
        }
        ThreadGroup g = group;
        if (g != null && newPriority > g.getMaxPriority()) {
            newPriority = g.getMaxPriority();
        }
        synchronized (this) {
            priority = newPriority;
            if (started) {
                setPriority0(newPriority);
            }
        }
    }

    public void interrupt() {
        synchronized (this) {
            if (!started) {
                pendingInterrupt = true;
                return;
            }
        }
        interrupt0();
    }

    public boolean isInterrupted() {
        synchronized (this) {
            if (!started) {
                return pendingInterrupt;
            }
        }
        return interrupted0(false);
    }

    public static boolean interrupted() {
        return currentThread().interrupted0(true);
    }

    public static void sleep(long millis) throws InterruptedException {
        if (millis < 0) {
            throw new IllegalArgumentException("timeout value is negative");
        }
        sleep0(toNanos(millis));
    }

    public static void sleep(long millis, int nanos) throws InterruptedException {
        if (millis < 0) {
            throw new IllegalArgumentException("timeout value is negative");
        }
        if (nanos < 0 || nanos > 999999) {
            throw new IllegalArgumentException("nanosecond timeout value out of range");
        }
        if (nanos >= 500000 || (nanos != 0 && millis == 0)) {
            millis++;
        }
        sleep(millis);
    }

    public final void join() throws InterruptedException {
        join0(0L);
    }

    public final void join(long millis) throws InterruptedException {
        if (millis < 0) {
            throw new IllegalArgumentException("timeout value is negative");
        }
        join0(toNanos(millis));
    }

    public final void join(long millis, int nanos) throws InterruptedException {
        if (millis < 0) {
            throw new IllegalArgumentException("timeout value is negative");
        }
        if (nanos < 0 || nanos > 999999) {
            throw new IllegalArgumentException("nanosecond timeout value out of range");
        }
        if (nanos >= 500000 || (nanos != 0 && millis == 0)) {
            millis++;
        }
        join(millis);
    }

    // Saturates instead of overflowing; 0 stays 0 (join's "wait forever").
    private static long toNanos(long millis) {
        if (millis >= Long.MAX_VALUE / 1000000L) {
            return Long.MAX_VALUE;
        }
        return millis * 1000000L;
    }

    public UncaughtExceptionHandler getUncaughtExceptionHandler() {
        UncaughtExceptionHandler handler = uncaughtExceptionHandler;
        if (handler != null) {
            return handler;
        }
        // A terminated thread has left its group (JDK 8 Thread.exit).
        return group;
    }

    public void setUncaughtExceptionHandler(UncaughtExceptionHandler handler) {
        uncaughtExceptionHandler = handler;
    }

    public static UncaughtExceptionHandler getDefaultUncaughtExceptionHandler() {
        return defaultUncaughtExceptionHandler;
    }

    public static void setDefaultUncaughtExceptionHandler(UncaughtExceptionHandler handler) {
        defaultUncaughtExceptionHandler = handler;
    }

    public String toString() {
        ThreadGroup g = group;
        String groupName = g == null ? "" : g.getName();
        return "Thread[" + getName() + "," + getPriority() + "," + groupName + "]";
    }

    public static native void yield();

    public static native boolean holdsLock(Object obj);

    private static native Thread current0();

    private static native void attachMain0(Thread main);

    private native void start0(boolean daemon, boolean interrupted, int priority);

    private native void setPriority0(int priority);

    private native boolean alive0();

    private native int state0();

    private native void interrupt0();

    private native boolean interrupted0(boolean clear);

    private static native void sleep0(long nanos) throws InterruptedException;

    private native void join0(long nanos) throws InterruptedException;
}
