package java.net;

/**
 * Internal bridge for the TLS layer (javax.net.ssl lives in another package):
 * reads and replaces the host handle under a Socket. Not part of the Java API.
 */
public final class BendSocketAccess {
    private BendSocketAccess() {
    }

    public static int handle(Socket socket) {
        return socket.handle;
    }

    public static void replaceHandle(Socket socket, int handle) {
        socket.handle = handle;
    }

    public static String peerHost(Socket socket) {
        return socket.peerHost();
    }
}
