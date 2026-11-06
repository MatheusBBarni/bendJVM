// Thread priorities weight BendJVM's scheduler: a priority-10 thread gets twice
// a normal quantum and a priority-1 thread a fifth of one (plan 05).
public class ThreadPriorities {
    static volatile boolean stop;
    static volatile int ready;

    static class Counter extends Thread {
        long count;

        Counter(int priority) {
            setPriority(priority);
        }

        public void run() {
            synchronized (ThreadPriorities.class) {
                ready++;
            }
            while (ready < 2) {
                Thread.yield();
            }
            while (!stop) {
                count++;
            }
        }
    }

    public static void main(String[] args) throws Exception {
        Counter high = new Counter(Thread.MAX_PRIORITY);
        Counter low = new Counter(Thread.MIN_PRIORITY);
        System.out.println("priorities: " + high.getPriority() + " " + low.getPriority());
        try {
            high.setPriority(11);
        } catch (IllegalArgumentException expected) {
            System.out.println("out of range rejected");
        }
        high.start();
        low.start();
        Thread.currentThread().setPriority(Thread.MIN_PRIORITY);
        while (ready < 2) {
            Thread.yield();
        }
        for (int i = 0; i < 20; i++) {
            Thread.yield();
        }
        stop = true;
        high.join();
        low.join();
        System.out.println("high ran more: " + (high.count > 3 * low.count));
    }
}
