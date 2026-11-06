import java.net.ServerSocket;

// Returning from main ends the VM when only daemon threads remain, even if they
// are blocked on I/O or sleeping (plan 05).
public class DaemonExit {
    public static void main(String[] args) throws Exception {
        final ServerSocket server = new ServerSocket(0);
        Thread acceptor = new Thread(new Runnable() {
            public void run() {
                try {
                    server.accept();
                } catch (Exception error) {
                    System.out.println("unexpected " + error);
                }
            }
        });
        acceptor.setDaemon(true);
        acceptor.start();
        Thread sleeper = new Thread(new Runnable() {
            public void run() {
                try {
                    Thread.sleep(600000);
                } catch (InterruptedException error) {
                    System.out.println("unexpected interrupt");
                }
            }
        });
        sleeper.setDaemon(true);
        sleeper.start();
        // A non-daemon worker finishing after main still keeps the VM alive until it ends.
        Thread worker = new Thread(new Runnable() {
            public void run() {
                for (int i = 0; i < 3000; i++) {
                    Thread.yield();
                }
                System.out.println("worker finished after main");
            }
        });
        worker.start();
        System.out.println("main returns; daemons alive: " + acceptor.isAlive() + " " + sleeper.isAlive());
    }
}
