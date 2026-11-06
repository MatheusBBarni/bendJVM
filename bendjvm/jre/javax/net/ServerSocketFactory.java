package javax.net;

import java.io.IOException;
import java.net.ServerSocket;

public abstract class ServerSocketFactory {
    protected ServerSocketFactory() {
    }

    public static ServerSocketFactory getDefault() {
        return new ServerSocketFactory() {
            public ServerSocket createServerSocket(int port) throws IOException {
                return new ServerSocket(port);
            }
        };
    }

    public abstract ServerSocket createServerSocket(int port) throws IOException;
}
