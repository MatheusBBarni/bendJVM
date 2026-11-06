// The ThreadGroup API (plan 05): hierarchy, membership, priorities,
// enumeration, interruption and group uncaught-exception handling.
public class ThreadGroups {
    static final Object gate = new Object();
    static boolean open;
    static int waiting;
    static int interrupted;

    static Runnable waiter(final String label) {
        return new Runnable() {
            public void run() {
                synchronized (gate) {
                    waiting++;
                    gate.notifyAll();
                    while (!open) {
                        try {
                            gate.wait();
                        } catch (InterruptedException e) {
                            interrupted++;
                            return;
                        }
                    }
                }
            }
        };
    }

    static void awaitWaiting(int count) throws InterruptedException {
        synchronized (gate) {
            while (waiting < count) {
                gate.wait();
            }
        }
    }

    public static void main(String[] args) throws Exception {
        ThreadGroup main = Thread.currentThread().getThreadGroup();
        System.out.println("main group: " + main.getName() + " parent " + main.getParent().getName() + " " + main);
        ThreadGroup workers = new ThreadGroup("workers");
        ThreadGroup nested = new ThreadGroup(workers, "nested");
        System.out.println("parents: " + (workers.getParent() == main) + " " + main.parentOf(nested) + " " + nested.parentOf(workers));
        workers.setMaxPriority(7);
        System.out.println("max priorities: " + workers.getMaxPriority() + " " + nested.getMaxPriority());

        Thread a = new Thread(workers, waiter("a"), "a");
        Thread b = new Thread(nested, waiter("b"), "b", 0);
        System.out.println("group of new thread: " + a.getThreadGroup().getName() + " priority " + a.getPriority());
        a.setPriority(Thread.MAX_PRIORITY);
        System.out.println("capped priority: " + a.getPriority());
        a.start();
        b.start();
        awaitWaiting(2);
        System.out.println("active: " + workers.activeCount() + " groups " + workers.activeGroupCount());
        Thread[] list = new Thread[4];
        int n = workers.enumerate(list);
        StringBuilder names = new StringBuilder();
        for (int i = 0; i < n; i++) {
            names.append(list[i].getName()).append(' ');
        }
        System.out.println("enumerated " + n + ": " + names.toString().trim());
        System.out.println("not recursive: " + workers.enumerate(new Thread[4], false));
        ThreadGroup[] groups = new ThreadGroup[4];
        System.out.println("subgroups: " + workers.enumerate(groups) + " " + groups[0].getName());

        workers.interrupt();
        a.join();
        b.join();
        System.out.println("interrupted by the group: " + interrupted);
        System.out.println("after join active: " + workers.activeCount() + " group of dead thread: " + a.getThreadGroup());

        // An uncaught exception goes to the thread's group before the default handler.
        ThreadGroup handling = new ThreadGroup("handling") {
            public void uncaughtException(Thread t, Throwable e) {
                System.out.println("group " + getName() + " saw " + e.getMessage() + " from " + t.getName());
            }
        };
        Thread failing = new Thread(handling, new Runnable() {
            public void run() {
                throw new IllegalStateException("group failure");
            }
        }, "failing");
        failing.start();
        failing.join();
        System.out.println("thread uses group handler: " + (failing.getUncaughtExceptionHandler() == null));
        try {
            new ThreadGroup(null, "orphan");
        } catch (NullPointerException expected) {
            System.out.println("null parent: " + expected.getClass().getName());
        }
    }
}
