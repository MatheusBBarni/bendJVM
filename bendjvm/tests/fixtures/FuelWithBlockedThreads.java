import java.net.ServerSocket;

// Fuel runs out while other threads wait on the host: the run ends promptly
// with OutOfFuel and its sockets are released (plan 05).
public class FuelWithBlockedThreads {
    public static void main(String[] args) throws Exception {
        final ServerSocket server = new ServerSocket(0);
        new Thread(new Runnable() {
            public void run() {
                try {
                    server.accept();
                } catch (Exception error) {
                    System.out.println("accept " + error);
                }
            }
        }).start();
        long spins = 0;
        while (true) {
            spins++;
        }
    }
}
