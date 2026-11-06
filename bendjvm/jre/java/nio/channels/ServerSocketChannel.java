package java.nio.channels;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import sun.nio.ch.HostIO;

public class ServerSocketChannel extends SelectableChannel {
    private final Object stateLock = new Object();
    private int handle;

    protected ServerSocketChannel() {
    }

    public static ServerSocketChannel open() throws IOException {
        return new ServerSocketChannel();
    }

    public final int validOps() {
        return SelectionKey.OP_ACCEPT;
    }

    public int hostHandle() {
        synchronized (stateLock) {
            return handle;
        }
    }

    public final ServerSocketChannel bind(SocketAddress local) throws IOException {
        return bind(local, 0);
    }

    public ServerSocketChannel bind(SocketAddress local, int backlog) throws IOException {
        synchronized (stateLock) {
            ensureOpen();
            if (handle != 0) {
                throw new AlreadyBoundException();
            }
            if (local != null && !(local instanceof InetSocketAddress)) {
                throw new UnsupportedAddressTypeException();
            }
            int port = local == null ? 0 : ((InetSocketAddress) local).getPort();
            handle = HostIO.call(HostIO.LISTEN, backlog < 1 ? 50 : backlog, port);
        }
        return this;
    }

    public SocketAddress getLocalAddress() throws IOException {
        synchronized (stateLock) {
            ensureOpen();
            if (handle == 0) {
                return null;
            }
            return new InetSocketAddress(HostIO.call(HostIO.LOCAL_PORT, handle, 0));
        }
    }

    // A connection, or null when non-blocking and none is waiting.
    public SocketChannel accept() throws IOException {
        int h;
        synchronized (stateLock) {
            ensureOpen();
            if (handle == 0) {
                throw new NotYetBoundException();
            }
            h = handle;
        }
        int accepted;
        try {
            accepted = HostIO.call(HostIO.ACCEPT, h, HostIO.FOREVER | flags());
        } catch (ClosedByInterruptException error) {
            throw interrupted(error);
        }
        if (accepted == 0) {
            return null;
        }
        String host = HostIO.text(HostIO.REMOTE_HOST, accepted, 0);
        int port = HostIO.call(HostIO.REMOTE_PORT, accepted, 0);
        return new SocketChannel(accepted, new InetSocketAddress(host == null || host.length() == 0 ? "0.0.0.0" : host, port));
    }

    protected void implCloseChannel() throws IOException {
        int h;
        synchronized (stateLock) {
            h = handle;
        }
        if (h != 0) {
            HostIO.call(HostIO.CLOSE, h, 0);
        }
    }

    public String toString() {
        return getClass().getName() + "[" + (isOpen() ? "open" : "closed") + "]";
    }
}
