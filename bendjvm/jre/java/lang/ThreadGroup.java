package java.lang;

import java.io.PrintStream;

/**
 * Thread groups (JDK 8 API). The tree starts at "system" with "main" below it;
 * a started thread is a member of its group until its run() finishes.
 */
public class ThreadGroup implements Thread.UncaughtExceptionHandler {
    private final ThreadGroup parent;
    private final String name;
    private int maxPriority;
    private boolean daemon;
    private boolean destroyed;
    private Thread[] threads = new Thread[4];
    private int threadCount;
    private ThreadGroup[] groups = new ThreadGroup[4];
    private int groupCount;

    // The root "system" group.
    private ThreadGroup() {
        this.parent = null;
        this.name = "system";
        this.maxPriority = Thread.MAX_PRIORITY;
    }

    public ThreadGroup(String name) {
        this(Thread.currentThread().getThreadGroup(), name);
    }

    public ThreadGroup(ThreadGroup parent, String name) {
        if (parent == null) {
            throw new NullPointerException();
        }
        this.name = name;
        this.parent = parent;
        synchronized (parent) {
            if (parent.destroyed) {
                throw new IllegalThreadStateException();
            }
            this.maxPriority = parent.maxPriority;
            this.daemon = parent.daemon;
            parent.addGroup(this);
        }
    }

    static ThreadGroup mainGroup() {
        return new ThreadGroup(new ThreadGroup(), "main");
    }

    public final String getName() {
        return name;
    }

    public final ThreadGroup getParent() {
        return parent;
    }

    public final synchronized int getMaxPriority() {
        return maxPriority;
    }

    public final synchronized boolean isDaemon() {
        return daemon;
    }

    public final synchronized void setDaemon(boolean daemon) {
        this.daemon = daemon;
    }

    public synchronized boolean isDestroyed() {
        return destroyed;
    }

    /** Out-of-range values are ignored; the parent's maximum caps the new one. */
    public final void setMaxPriority(int pri) {
        ThreadGroup[] children;
        synchronized (this) {
            if (pri < Thread.MIN_PRIORITY || pri > Thread.MAX_PRIORITY) {
                return;
            }
            maxPriority = parent != null ? Math.min(pri, parent.getMaxPriority()) : pri;
            children = snapshotGroups();
        }
        for (ThreadGroup child : children) {
            child.setMaxPriority(pri);
        }
    }

    public final boolean parentOf(ThreadGroup g) {
        for (; g != null; g = g.parent) {
            if (g == this) {
                return true;
            }
        }
        return false;
    }

    public final void checkAccess() {
    }

    private ThreadGroup[] snapshotGroups() {
        ThreadGroup[] copy = new ThreadGroup[groupCount];
        System.arraycopy(groups, 0, copy, 0, groupCount);
        return copy;
    }

    private Thread[] snapshotThreads() {
        Thread[] copy = new Thread[threadCount];
        System.arraycopy(threads, 0, copy, 0, threadCount);
        return copy;
    }

    public int activeCount() {
        int count;
        ThreadGroup[] children;
        synchronized (this) {
            if (destroyed) {
                return 0;
            }
            count = threadCount;
            children = snapshotGroups();
        }
        for (ThreadGroup child : children) {
            count += child.activeCount();
        }
        return count;
    }

    public int activeGroupCount() {
        int count;
        ThreadGroup[] children;
        synchronized (this) {
            if (destroyed) {
                return 0;
            }
            count = groupCount;
            children = snapshotGroups();
        }
        for (ThreadGroup child : children) {
            count += child.activeGroupCount();
        }
        return count;
    }

    public int enumerate(Thread[] list) {
        return enumerate(list, 0, true);
    }

    public int enumerate(Thread[] list, boolean recurse) {
        return enumerate(list, 0, recurse);
    }

    private int enumerate(Thread[] list, int n, boolean recurse) {
        Thread[] members;
        ThreadGroup[] children;
        synchronized (this) {
            if (destroyed) {
                return n;
            }
            members = snapshotThreads();
            children = recurse ? snapshotGroups() : new ThreadGroup[0];
        }
        for (Thread t : members) {
            if (n >= list.length) {
                return n;
            }
            if (t.isAlive()) {
                list[n++] = t;
            }
        }
        for (ThreadGroup child : children) {
            n = child.enumerate(list, n, true);
        }
        return n;
    }

    public int enumerate(ThreadGroup[] list) {
        return enumerate(list, 0, true);
    }

    public int enumerate(ThreadGroup[] list, boolean recurse) {
        return enumerate(list, 0, recurse);
    }

    private int enumerate(ThreadGroup[] list, int n, boolean recurse) {
        ThreadGroup[] children;
        synchronized (this) {
            if (destroyed) {
                return n;
            }
            children = snapshotGroups();
        }
        for (ThreadGroup child : children) {
            if (n >= list.length) {
                return n;
            }
            list[n++] = child;
            if (recurse) {
                n = child.enumerate(list, n, true);
            }
        }
        return n;
    }

    public final void interrupt() {
        Thread[] members;
        ThreadGroup[] children;
        synchronized (this) {
            members = snapshotThreads();
            children = snapshotGroups();
        }
        for (Thread t : members) {
            t.interrupt();
        }
        for (ThreadGroup child : children) {
            child.interrupt();
        }
    }

    public final void destroy() {
        ThreadGroup[] children;
        synchronized (this) {
            if (destroyed || threadCount > 0) {
                throw new IllegalThreadStateException();
            }
            children = snapshotGroups();
        }
        for (ThreadGroup child : children) {
            child.destroy();
        }
        synchronized (this) {
            destroyed = true;
            groupCount = 0;
            groups = new ThreadGroup[0];
        }
        if (parent != null) {
            parent.removeGroup(this);
        }
    }

    private synchronized void addGroup(ThreadGroup g) {
        if (groupCount == groups.length) {
            ThreadGroup[] grown = new ThreadGroup[groupCount * 2 + 1];
            System.arraycopy(groups, 0, grown, 0, groupCount);
            groups = grown;
        }
        groups[groupCount++] = g;
    }

    private synchronized void removeGroup(ThreadGroup g) {
        for (int i = 0; i < groupCount; i++) {
            if (groups[i] == g) {
                System.arraycopy(groups, i + 1, groups, i, groupCount - i - 1);
                groups[--groupCount] = null;
                break;
            }
        }
        if (daemon && threadCount == 0 && groupCount == 0 && !destroyed) {
            destroyQuietly();
        }
    }

    // A thread joins its group when it starts.
    synchronized void add(Thread t) {
        if (destroyed) {
            throw new IllegalThreadStateException();
        }
        if (threadCount == threads.length) {
            Thread[] grown = new Thread[threadCount * 2 + 1];
            System.arraycopy(threads, 0, grown, 0, threadCount);
            threads = grown;
        }
        threads[threadCount++] = t;
    }

    // ...and leaves it when its run() has finished; an empty daemon group is destroyed.
    void threadTerminated(Thread t) {
        boolean empty;
        synchronized (this) {
            for (int i = 0; i < threadCount; i++) {
                if (threads[i] == t) {
                    System.arraycopy(threads, i + 1, threads, i, threadCount - i - 1);
                    threads[--threadCount] = null;
                    break;
                }
            }
            notifyAll();
            empty = daemon && threadCount == 0 && groupCount == 0 && !destroyed;
        }
        if (empty) {
            destroyQuietly();
        }
    }

    private void destroyQuietly() {
        try {
            destroy();
        } catch (IllegalThreadStateException raced) {
            // a thread joined the group meanwhile
        }
    }

    synchronized void checkStart() {
        if (destroyed) {
            throw new IllegalThreadStateException();
        }
    }

    public void list() {
        list(System.out, 0);
    }

    private void list(PrintStream out, int indent) {
        Thread[] members;
        ThreadGroup[] children;
        synchronized (this) {
            members = snapshotThreads();
            children = snapshotGroups();
        }
        StringBuilder pad = new StringBuilder();
        for (int i = 0; i < indent; i++) {
            pad.append(' ');
        }
        out.println(pad + toString());
        for (Thread t : members) {
            out.println(pad + "    " + t);
        }
        for (ThreadGroup child : children) {
            child.list(out, indent + 4);
        }
    }

    /** The parent group's handler first, then the default handler, then the JDK report. */
    public void uncaughtException(Thread t, Throwable e) {
        if (parent != null) {
            parent.uncaughtException(t, e);
            return;
        }
        Thread.UncaughtExceptionHandler handler = Thread.getDefaultUncaughtExceptionHandler();
        if (handler != null) {
            handler.uncaughtException(t, e);
        } else {
            System.err.print("Exception in thread \"" + t.getName() + "\" ");
            e.printStackTrace(System.err);
        }
    }

    public String toString() {
        return getClass().getName() + "[name=" + getName() + ",maxpri=" + getMaxPriority() + "]";
    }
}
