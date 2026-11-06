package java.net;

import java.io.IOException;
import sun.nio.ch.HostIO;

public class ServerSocket implements java.io.Closeable {
    int handle;
    private boolean closed;
    private int soTimeout;
    private final Object stateLock = new Object();

    public ServerSocket() throws IOException {
    }

    public ServerSocket(int port) throws IOException {
        this(port, 50);
    }

    public ServerSocket(int port, int backlog) throws IOException {
        if (port < 0 || port > 0xFFFF) {
            throw new IllegalArgumentException("Port value out of range: " + port);
        }
        bind(new InetSocketAddress(port), backlog);
    }

    public void bind(SocketAddress endpoint) throws IOException {
        bind(endpoint, 50);
    }

    public void bind(SocketAddress endpoint, int backlog) throws IOException {
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket is closed");
            }
            if (handle != 0) {
                throw new SocketException("Already bound");
            }
        }
        int port = endpoint == null ? 0 : ((InetSocketAddress) endpoint).getPort();
        int bound = HostIO.call(HostIO.LISTEN, backlog < 1 ? 50 : backlog, port);
        synchronized (stateLock) {
            handle = bound;
        }
    }

    public Socket accept() throws IOException {
        int h;
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket is closed");
            }
            if (handle == 0) {
                throw new SocketException("Socket is not bound yet");
            }
            h = handle;
        }
        int accepted = HostIO.call(HostIO.ACCEPT, h, HostIO.timeoutArg(soTimeout));
        return accepted(accepted);
    }

    // SSLServerSocket wraps accepted connections.
    Socket accepted(int handle) throws IOException {
        return new Socket(handle, HostIO.text(HostIO.REMOTE_HOST, handle, 0), HostIO.call(HostIO.REMOTE_PORT, handle, 0));
    }

    public int getLocalPort() {
        synchronized (stateLock) {
            if (handle == 0) {
                return -1;
            }
        }
        try {
            return HostIO.call(HostIO.LOCAL_PORT, handle, 0);
        } catch (IOException error) {
            return -1;
        }
    }

    public void setSoTimeout(int timeout) throws SocketException {
        if (isClosed()) {
            throw new SocketException("Socket is closed");
        }
        if (timeout < 0) {
            throw new IllegalArgumentException("timeout can't be negative");
        }
        soTimeout = timeout;
    }

    public int getSoTimeout() throws IOException {
        return soTimeout;
    }

    public void close() throws IOException {
        int h;
        synchronized (stateLock) {
            if (closed) {
                return;
            }
            closed = true;
            h = handle;
        }
        if (h != 0) {
            HostIO.call(HostIO.CLOSE, h, 0);
        }
    }

    public boolean isClosed() {
        synchronized (stateLock) {
            return closed;
        }
    }

    public boolean isBound() {
        synchronized (stateLock) {
            return handle != 0;
        }
    }

    public String toString() {
        if (!isBound()) {
            return "ServerSocket[unbound]";
        }
        return "ServerSocket[addr=0.0.0.0/0.0.0.0,localport=" + getLocalPort() + "]";
    }
}
