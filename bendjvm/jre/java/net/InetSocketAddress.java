package java.net;

/**
 * A host and port. Like the JDK, the (String, int) constructor resolves the name
 * at once; when that fails the address is unresolved and connecting to it fails.
 */
public class InetSocketAddress extends SocketAddress {
    private final String hostname;
    private final InetAddress addr;
    private final int port;

    public InetSocketAddress(String hostname, int port) {
        if (hostname == null) {
            throw new IllegalArgumentException("hostname can't be null");
        }
        this.port = checkPort(port);
        InetAddress resolved;
        try {
            resolved = InetAddress.getByName(hostname);
        } catch (UnknownHostException unresolved) {
            resolved = null;
        }
        this.addr = resolved;
        this.hostname = resolved == null ? hostname : null;
    }

    public InetSocketAddress(InetAddress addr, int port) {
        this.port = checkPort(port);
        this.addr = addr == null ? InetAddress.anyLocal() : addr;
        this.hostname = null;
    }

    public InetSocketAddress(int port) {
        this(InetAddress.anyLocal(), port);
    }

    private InetSocketAddress(int port, String hostname) {
        this.port = port;
        this.hostname = hostname;
        this.addr = null;
    }

    public static InetSocketAddress createUnresolved(String host, int port) {
        if (host == null) {
            throw new IllegalArgumentException("hostname can't be null");
        }
        return new InetSocketAddress(checkPort(port), host);
    }

    private static int checkPort(int port) {
        if (port < 0 || port > 0xFFFF) {
            throw new IllegalArgumentException("port out of range:" + port);
        }
        return port;
    }

    public final int getPort() {
        return port;
    }

    public final InetAddress getAddress() {
        return addr;
    }

    public final boolean isUnresolved() {
        return addr == null;
    }

    public final String getHostName() {
        return hostname != null ? hostname : addr.getHostName();
    }

    public final String getHostString() {
        if (hostname != null) {
            return hostname;
        }
        return addr.getHostName();
    }

    // The text the host connects to: the resolved address when there is one.
    String connectHost() {
        return addr != null ? addr.getHostAddress() : hostname;
    }

    public boolean equals(Object other) {
        if (!(other instanceof InetSocketAddress)) {
            return false;
        }
        InetSocketAddress that = (InetSocketAddress) other;
        if (port != that.port) {
            return false;
        }
        if (addr != null) {
            return addr.equals(that.addr);
        }
        return that.addr == null && hostname.equals(that.hostname);
    }

    public int hashCode() {
        return (addr != null ? addr.hashCode() : hostname.hashCode()) + port;
    }

    public String toString() {
        if (isUnresolved()) {
            return hostname + ":" + port;
        }
        return addr.toString() + ":" + port;
    }
}
