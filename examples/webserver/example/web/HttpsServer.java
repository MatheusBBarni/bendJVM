package example.web;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Socket;
import java.net.SocketException;
import java.net.SocketTimeoutException;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.SSLSocket;

/**
 * A small HTTPS/1.1 server: one acceptor thread, a monitor-protected work queue,
 * worker threads, a volatile shutdown flag and a native checksum route. Every
 * response closes its connection ("Connection: close" with Content-Length).
 */
public final class HttpsServer {
    private static final int WORKERS = 3;

    private final SSLServerSocket server;
    private final WorkQueue queue = new WorkQueue(8);
    private volatile boolean shuttingDown;
    private int served;

    HttpsServer(int port) throws IOException {
        server = (SSLServerSocket) SSLServerSocketFactory.getDefault().createServerSocket(port);
    }

    private synchronized int countServed() {
        return ++served;
    }

    private synchronized int servedSoFar() {
        return served;
    }

    void run() throws InterruptedException {
        Thread[] workers = new Thread[WORKERS];
        for (int i = 0; i < WORKERS; i++) {
            workers[i] = new Thread(new Runnable() {
                public void run() {
                    work();
                }
            }, "worker-" + i);
            workers[i].start();
        }
        Thread acceptor = new Thread(new Runnable() {
            public void run() {
                accept();
            }
        }, "acceptor");
        acceptor.start();
        System.out.println("listening on " + server.getLocalPort());
        acceptor.join();
        queue.close();
        for (Thread worker : workers) {
            worker.join();
        }
        System.out.println("stopped after " + servedSoFar() + " requests");
    }

    private void accept() {
        while (!shuttingDown) {
            try {
                Socket socket = server.accept();
                socket.setSoTimeout(60000);
                queue.put(socket);
            } catch (SocketException closed) {
                if (!shuttingDown) {
                    System.out.println("accept failed: " + closed.getMessage());
                }
                return;
            } catch (IOException | InterruptedException error) {
                System.out.println("accept failed: " + error);
                return;
            }
        }
    }

    private void work() {
        for (;;) {
            Socket socket;
            try {
                socket = queue.take();
            } catch (InterruptedException interrupted) {
                return;
            }
            if (socket == null) {
                return;
            }
            try {
                handle(socket);
            } catch (SocketTimeoutException slow) {
                // a client that stalls past the read timeout is dropped
            } catch (IOException error) {
                // the client went away or failed the handshake
            } finally {
                try {
                    socket.close();
                } catch (IOException ignored) {
                    // already closed
                }
            }
        }
    }

    private static String readLine(InputStream in) throws IOException {
        StringBuilder line = new StringBuilder();
        int b;
        while ((b = in.read()) != -1) {
            if (b == '\n') {
                break;
            }
            if (b != '\r') {
                line.append((char) b);
            }
        }
        return line.toString();
    }

    private void handle(Socket socket) throws IOException {
        ((SSLSocket) socket).startHandshake();
        InputStream in = socket.getInputStream();
        String requestLine = readLine(in);
        int contentLength = 0;
        for (String header = readLine(in); !header.isEmpty(); header = readLine(in)) {
            if (header.toLowerCase().startsWith("content-length:")) {
                contentLength = Integer.parseInt(header.substring(15).trim());
            }
        }
        byte[] body = new byte[contentLength];
        for (int read = 0; read < contentLength; ) {
            int n = in.read(body, read, contentLength - read);
            if (n < 0) {
                throw new IOException("truncated body");
            }
            read += n;
        }
        int firstSpace = requestLine.indexOf(' ');
        int secondSpace = firstSpace < 0 ? -1 : requestLine.indexOf(' ', firstSpace + 1);
        if (secondSpace < 0 || !requestLine.substring(secondSpace + 1).startsWith("HTTP/1.")) {
            respond(socket, 400, "bad request\n");
            return;
        }
        String method = requestLine.substring(0, firstSpace);
        String path = requestLine.substring(firstSpace + 1, secondSpace);
        if (method.equals("GET") && path.equals("/hello")) {
            respond(socket, 200, "hello from " + Thread.currentThread().getName().substring(0, 6) + " over "
                + ((SSLSocket) socket).getSession().getProtocol().startsWith("TLSv1.") + "\n");
        } else if (method.equals("POST") && path.equals("/checksum")) {
            respond(socket, 200, "fnv1a " + Integer.toHexString(Checksum.fnv1a(body)) + "\n");
        } else if (method.equals("GET") && path.equals("/stats")) {
            respond(socket, 200, "served " + servedSoFar() + "\n");
        } else if (method.equals("POST") && path.equals("/shutdown")) {
            shuttingDown = true;
            respond(socket, 200, "bye\n");
            server.close();
        } else {
            respond(socket, 404, "not found\n");
        }
    }

    private void respond(Socket socket, int status, String text) throws IOException {
        byte[] body = text.getBytes("UTF-8");
        String reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Bad Request";
        String head = "HTTP/1.1 " + status + " " + reason + "\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: "
            + body.length + "\r\nConnection: close\r\n\r\n";
        OutputStream out = socket.getOutputStream();
        out.write(head.getBytes("UTF-8"));
        out.write(body);
        out.flush();
        countServed();
    }

    public static void main(String[] args) throws Exception {
        new HttpsServer(args.length > 0 ? Integer.parseInt(args[0]) : 0).run();
    }
}
