package java.net;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import sun.nio.ch.HostIO;

/**
 * A TCP client socket over the host's non-blocking sockets: a blocked connect,
 * read or write parks only its own Java thread. Classic sockets are not
 * interruptible (unlike NIO channels); closing one from another thread fails
 * the blocked operation with SocketException.
 */
public class Socket implements java.io.Closeable {
    // The host socket handle (0 until connected). Subclasses (SSLSocket) replace it.
    int handle;
    private boolean closed;
    private boolean inputShutdown;
    private boolean outputShutdown;
    private int soTimeout;
    private String host;
    private int port;
    private InputStream in;
    private OutputStream out;
    private final Object stateLock = new Object();

    public Socket() {
    }

    public Socket(String host, int port) throws IOException {
        connect(new InetSocketAddress(host == null ? "localhost" : host, port), 0);
    }

    // An accepted connection.
    Socket(int handle, String host, int port) {
        this.handle = handle;
        this.host = host;
        this.port = port;
    }

    public void connect(SocketAddress endpoint) throws IOException {
        connect(endpoint, 0);
    }

    public void connect(SocketAddress endpoint, int timeout) throws IOException {
        if (endpoint == null) {
            throw new IllegalArgumentException("connect: The address can't be null");
        }
        if (timeout < 0) {
            throw new IllegalArgumentException("connect: timeout can't be negative");
        }
        if (!(endpoint instanceof InetSocketAddress)) {
            throw new IllegalArgumentException("Unsupported address type");
        }
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket is closed");
            }
            if (handle != 0) {
                throw new SocketException("already connected");
            }
        }
        InetSocketAddress address = (InetSocketAddress) endpoint;
        if (address.isUnresolved()) {
            throw new UnknownHostException(address.getHostName());
        }
        int connected = HostIO.connect(address.connectHost(), address.getPort(), timeout, 0);
        synchronized (stateLock) {
            handle = connected;
            host = address.getHostString();
            port = address.getPort();
        }
    }

    // Reads into b[off, off+len): the byte count, or -1 at end of stream.
    int readInto(byte[] b, int off, int len) throws IOException {
        int h = openHandle();
        return HostIO.call(HostIO.READ, h, HostIO.timeoutArg(soTimeout), b, off, len);
    }

    void writeFrom(byte[] b, int off, int len) throws IOException {
        if (outputShutdown) {
            throw new SocketException("Socket output is shutdown");
        }
        int h = openHandle();
        while (len > 0) {
            int n = HostIO.call(HostIO.WRITE, h, 0, b, off, len);
            off += n;
            len -= n;
        }
    }

    int openHandle() throws SocketException {
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket closed");
            }
            if (handle == 0) {
                throw new SocketException("Socket is not connected");
            }
            return handle;
        }
    }

    public InputStream getInputStream() throws IOException {
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket is closed");
            }
            if (handle == 0) {
                throw new SocketException("Socket is not connected");
            }
            if (inputShutdown) {
                throw new SocketException("Socket input is shutdown");
            }
            if (in == null) {
                in = new SocketInputStream(this);
            }
            return in;
        }
    }

    public OutputStream getOutputStream() throws IOException {
        synchronized (stateLock) {
            if (closed) {
                throw new SocketException("Socket is closed");
            }
            if (handle == 0) {
                throw new SocketException("Socket is not connected");
            }
            if (outputShutdown) {
                throw new SocketException("Socket output is shutdown");
            }
            if (out == null) {
                out = new SocketOutputStream(this);
            }
            return out;
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

    public int getSoTimeout() throws SocketException {
        if (isClosed()) {
            throw new SocketException("Socket is closed");
        }
        return soTimeout;
    }

    public void shutdownInput() throws IOException {
        int h = openHandle();
        if (inputShutdown) {
            throw new SocketException("Socket input is already shutdown");
        }
        HostIO.call(HostIO.SHUTDOWN, h, 0);
        inputShutdown = true;
    }

    public void shutdownOutput() throws IOException {
        int h = openHandle();
        if (outputShutdown) {
            throw new SocketException("Socket output is already shutdown");
        }
        HostIO.call(HostIO.SHUTDOWN, h, 1);
        outputShutdown = true;
    }

    public boolean isInputShutdown() {
        return inputShutdown;
    }

    public boolean isOutputShutdown() {
        return outputShutdown;
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

    public boolean isConnected() {
        synchronized (stateLock) {
            return handle != 0;
        }
    }

    public int getPort() {
        return port;
    }

    public int getLocalPort() {
        synchronized (stateLock) {
            if (handle == 0 || closed) {
                return -1;
            }
        }
        try {
            return HostIO.call(HostIO.LOCAL_PORT, handle, 0);
        } catch (IOException error) {
            return -1;
        }
    }

    String peerHost() {
        return host;
    }

    public InetAddress getInetAddress() {
        if (!isConnected()) {
            return null;
        }
        try {
            return InetAddress.getByName(host);
        } catch (UnknownHostException unknown) {
            return null;
        }
    }

    public void setTcpNoDelay(boolean on) throws SocketException {
        if (isClosed()) {
            throw new SocketException("Socket is closed");
        }
    }

    public String toString() {
        if (!isConnected()) {
            return "Socket[unconnected]";
        }
        return "Socket[addr=" + host + ",port=" + port + ",localport=" + getLocalPort() + "]";
    }
}
