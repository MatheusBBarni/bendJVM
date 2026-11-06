package java.nio.channels;

import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.SocketAddress;
import java.nio.ByteBuffer;
import sun.nio.ch.HostIO;

/**
 * A TCP connection channel. Buffer positions change only in Java: the host
 * receives the remaining slice and reports how many bytes it moved.
 */
public class SocketChannel extends SelectableChannel implements ByteChannel {
    private final Object stateLock = new Object();
    private int handle;
    private boolean connected;
    private boolean pending;
    private boolean inputShutdown;
    private boolean outputShutdown;
    private InetSocketAddress remote;

    protected SocketChannel() {
    }

    // An accepted connection.
    SocketChannel(int handle, InetSocketAddress remote) {
        this.handle = handle;
        this.connected = true;
        this.remote = remote;
    }

    public static SocketChannel open() throws IOException {
        return new SocketChannel();
    }

    public static SocketChannel open(SocketAddress remote) throws IOException {
        SocketChannel channel = open();
        try {
            channel.connect(remote);
        } catch (IOException error) {
            channel.close();
            throw error;
        }
        return channel;
    }

    public final int validOps() {
        return SelectionKey.OP_READ | SelectionKey.OP_WRITE | SelectionKey.OP_CONNECT;
    }

    public int hostHandle() {
        synchronized (stateLock) {
            return handle;
        }
    }

    public boolean isConnected() {
        synchronized (stateLock) {
            return connected;
        }
    }

    public boolean isConnectionPending() {
        synchronized (stateLock) {
            return pending;
        }
    }

    public boolean connect(SocketAddress endpoint) throws IOException {
        if (!(endpoint instanceof InetSocketAddress)) {
            throw new UnsupportedAddressTypeException();
        }
        InetSocketAddress address = (InetSocketAddress) endpoint;
        if (address.isUnresolved()) {
            throw new UnresolvedAddressException();
        }
        synchronized (stateLock) {
            ensureOpen();
            if (connected) {
                throw new AlreadyConnectedException();
            }
            if (pending) {
                throw new ConnectionPendingException();
            }
            pending = true;
        }
        int h;
        try {
            h = HostIO.connect(address.getAddress().getHostAddress(), address.getPort(), 0, flags());
        } catch (ClosedByInterruptException error) {
            throw interrupted(error);
        } catch (IOException error) {
            synchronized (stateLock) {
                pending = false;
            }
            throw error;
        }
        synchronized (stateLock) {
            handle = h;
            remote = address;
            if (isBlocking()) {
                pending = false;
                connected = true;
                return true;
            }
        }
        return finishConnect();
    }

    public boolean finishConnect() throws IOException {
        synchronized (stateLock) {
            ensureOpen();
            if (connected) {
                return true;
            }
            if (!pending) {
                throw new NoConnectionPendingException();
            }
        }
        int done;
        try {
            done = HostIO.call(HostIO.FINISH_CONNECT, handle, isBlocking() ? HostIO.INTERRUPTIBLE : HostIO.NONBLOCKING);
        } catch (ClosedByInterruptException error) {
            throw interrupted(error);
        } catch (IOException error) {
            synchronized (stateLock) {
                pending = false;
            }
            close();
            throw error;
        }
        synchronized (stateLock) {
            if (done != 0) {
                pending = false;
                connected = true;
            }
            return connected;
        }
    }

    private int openHandle() throws IOException {
        synchronized (stateLock) {
            ensureOpen();
            if (!connected) {
                throw new NotYetConnectedException();
            }
            return handle;
        }
    }

    public int read(ByteBuffer dst) throws IOException {
        if (dst == null) {
            throw new NullPointerException();
        }
        int h = openHandle();
        if (inputShutdown) {
            return -1;
        }
        int want = dst.remaining();
        if (want == 0) {
            return 0;
        }
        byte[] chunk = new byte[want];
        int n;
        try {
            n = HostIO.call(HostIO.READ, h, HostIO.FOREVER | flags(), chunk, 0, want);
        } catch (ClosedByInterruptException error) {
            throw interrupted(error);
        }
        if (n > 0) {
            dst.put(chunk, 0, n);
        }
        return n;
    }

    public int write(ByteBuffer src) throws IOException {
        if (src == null) {
            throw new NullPointerException();
        }
        int h = openHandle();
        if (outputShutdown) {
            throw new ClosedChannelException();
        }
        int have = src.remaining();
        if (have == 0) {
            return 0;
        }
        byte[] chunk = new byte[have];
        int start = src.position();
        src.get(chunk, 0, have);
        int n;
        try {
            n = HostIO.call(HostIO.WRITE, h, flags(), chunk, 0, have);
        } catch (ClosedByInterruptException error) {
            src.position(start);
            throw interrupted(error);
        } catch (IOException error) {
            src.position(start);
            throw error;
        }
        src.position(start + n);
        return n;
    }

    public SocketChannel shutdownInput() throws IOException {
        int h = openHandle();
        if (!inputShutdown) {
            HostIO.call(HostIO.SHUTDOWN, h, 0);
            inputShutdown = true;
        }
        return this;
    }

    public SocketChannel shutdownOutput() throws IOException {
        int h = openHandle();
        if (!outputShutdown) {
            HostIO.call(HostIO.SHUTDOWN, h, 1);
            outputShutdown = true;
        }
        return this;
    }

    public SocketAddress getRemoteAddress() throws IOException {
        ensureOpen();
        return remote;
    }

    protected void implCloseChannel() throws IOException {
        int h;
        synchronized (stateLock) {
            h = handle;
            connected = false;
            pending = false;
        }
        if (h != 0) {
            HostIO.call(HostIO.CLOSE, h, 0);
        }
    }

    public String toString() {
        return getClass().getName() + "[" + (isOpen() ? (isConnected() ? "connected remote=" + remote : "unconnected") : "closed") + "]";
    }
}
