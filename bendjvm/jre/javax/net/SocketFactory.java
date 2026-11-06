package javax.net;

import java.io.IOException;
import java.net.Socket;

public abstract class SocketFactory {
    protected SocketFactory() {
    }

    public static SocketFactory getDefault() {
        return new SocketFactory() {
            public Socket createSocket(String host, int port) throws IOException {
                return new Socket(host, port);
            }
        };
    }

    public Socket createSocket() throws IOException {
        return new Socket();
    }

    public abstract Socket createSocket(String host, int port) throws IOException;
}
