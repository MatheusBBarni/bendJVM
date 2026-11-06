import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.net.SocketTimeoutException;

// Blocking sockets served by several threads (plan 05): a client that stalls
// mid-request does not stop the others, and close/half-close behave like the JDK.
public class ConcurrentTcp {
    static volatile int served;

    static void serve(final Socket client) {
        new Thread(new Runnable() {
            public void run() {
                try {
                    InputStream in = client.getInputStream();
                    OutputStream out = client.getOutputStream();
                    StringBuilder line = new StringBuilder();
                    int b;
                    while ((b = in.read()) != -1 && b != '\n') {
                        line.append((char) b);
                    }
                    out.write(("echo " + line + "\n").getBytes("UTF-8"));
                    out.flush();
                    synchronized (ConcurrentTcp.class) {
                        served++;
                    }
                    client.close();
                } catch (IOException error) {
                    System.out.println("server error " + error);
                }
            }
        }).start();
    }

    static String request(int port, String text) throws IOException {
        Socket socket = new Socket("127.0.0.1", port);
        socket.getOutputStream().write((text + "\n").getBytes("UTF-8"));
        InputStream in = socket.getInputStream();
        StringBuilder reply = new StringBuilder();
        int b;
        while ((b = in.read()) != -1 && b != '\n') {
            reply.append((char) b);
        }
        socket.close();
        return reply.toString();
    }

    public static void main(String[] args) throws Exception {
        final ServerSocket server = new ServerSocket(0);
        final int port = server.getLocalPort();
        Thread acceptor = new Thread(new Runnable() {
            public void run() {
                try {
                    for (int i = 0; i < 4; i++) {
                        serve(server.accept());
                    }
                } catch (IOException error) {
                    System.out.println("accept error " + error);
                }
            }
        });
        acceptor.start();

        // A slow client: connected, sends half a line, then waits.
        Socket slow = new Socket("127.0.0.1", port);
        slow.getOutputStream().write("par".getBytes("UTF-8"));
        // Other clients are still served while the slow one stalls.
        System.out.println(request(port, "one"));
        System.out.println(request(port, "two"));
        System.out.println(request(port, "three"));
        slow.getOutputStream().write("tial\n".getBytes("UTF-8"));
        InputStream slowIn = slow.getInputStream();
        StringBuilder reply = new StringBuilder();
        int b;
        while ((b = slowIn.read()) != -1 && b != '\n') {
            reply.append((char) b);
        }
        System.out.println(reply);
        System.out.println("end of stream: " + slowIn.read());
        slow.close();
        acceptor.join();
        System.out.println("closed: " + slow.isClosed() + " connected: " + slow.isConnected());

        // Half-close: shutdownOutput delivers EOF while the reply still arrives.
        final ServerSocket second = new ServerSocket(0);
        Thread replier = new Thread(new Runnable() {
            public void run() {
                try {
                    Socket peer = second.accept();
                    InputStream in = peer.getInputStream();
                    int count = 0;
                    while (in.read() != -1) {
                        count++;
                    }
                    peer.getOutputStream().write(("got " + count + "\n").getBytes("UTF-8"));
                    peer.close();
                } catch (IOException error) {
                    System.out.println("replier error " + error);
                }
            }
        });
        replier.start();
        Socket half = new Socket("127.0.0.1", second.getLocalPort());
        half.getOutputStream().write(new byte[] {1, 2, 3, 4, 5});
        half.shutdownOutput();
        System.out.println("output shutdown: " + half.isOutputShutdown());
        InputStream halfIn = half.getInputStream();
        StringBuilder got = new StringBuilder();
        while ((b = halfIn.read()) != -1 && b != '\n') {
            got.append((char) b);
        }
        System.out.println(got);
        try {
            half.getOutputStream().write(1);
            System.out.println("wrote after shutdown");
        } catch (SocketException expected) {
            System.out.println("write after shutdown: " + expected.getMessage());
        }
        half.close();
        replier.join();

        // Closing a socket another thread is reading from wakes that reader.
        final ServerSocket third = new ServerSocket(0);
        final Socket idle = new Socket("127.0.0.1", third.getLocalPort());
        final Socket accepted = third.accept();
        Thread reader = new Thread(new Runnable() {
            public void run() {
                try {
                    idle.getInputStream().read();
                    System.out.println("read returned");
                } catch (SocketException expected) {
                    System.out.println("blocked read: " + expected.getClass().getName());
                } catch (IOException other) {
                    System.out.println("blocked read: " + other.getClass().getName());
                }
            }
        });
        reader.start();
        while (reader.getState() != Thread.State.RUNNABLE) {
            Thread.yield();
        }
        for (int i = 0; i < 2000; i++) {
            Thread.yield();
        }
        idle.close();
        reader.join();
        accepted.close();

        // Accept timeout.
        third.setSoTimeout(50);
        try {
            third.accept();
        } catch (SocketTimeoutException expected) {
            System.out.println("accept: " + expected.getMessage());
        }
        third.close();
        second.close();
        server.close();
        try {
            server.accept();
        } catch (SocketException expected) {
            System.out.println("closed server: " + expected.getMessage());
        }
        System.out.println("served " + served);
    }
}
