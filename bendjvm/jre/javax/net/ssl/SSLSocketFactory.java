package javax.net.ssl;

import java.io.IOException;
import java.net.Socket;
import javax.net.SocketFactory;

public abstract class SSLSocketFactory extends SocketFactory {
    public SSLSocketFactory() {
    }

    public static SocketFactory getDefault() {
        return SSLContext.defaultContext().getSocketFactory();
    }

    public abstract String[] getDefaultCipherSuites();

    public abstract String[] getSupportedCipherSuites();

    public abstract Socket createSocket(Socket s, String host, int port, boolean autoClose) throws IOException;
}
