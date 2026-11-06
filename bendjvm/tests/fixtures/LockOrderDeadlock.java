// Two threads taking two monitors in opposite orders. The JVM would hang;
// BendJVM reports the closed wait-for cycle as a deadlock diagnostic.
public class LockOrderDeadlock {
    static final Object first = new Object();
    static final Object second = new Object();
    static volatile int holding;

    static void lock(Object a, Object b) {
        synchronized (a) {
            synchronized (LockOrderDeadlock.class) {
                holding++;
            }
            while (holding < 2) {
                Thread.yield();
            }
            synchronized (b) {
                System.out.println("unreachable");
            }
        }
    }

    public static void main(String[] args) throws Exception {
        Thread other = new Thread(new Runnable() {
            public void run() {
                lock(second, first);
            }
        });
        other.start();
        lock(first, second);
    }
}
