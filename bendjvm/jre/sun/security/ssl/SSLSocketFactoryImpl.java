package sun.security.ssl;

import java.io.IOException;
import java.net.Socket;
import javax.net.ssl.SSLSocketFactory;

public final class SSLSocketFactoryImpl extends SSLSocketFactory {
    public Socket createSocket(String host, int port) throws IOException {
        return new SSLSocketImpl(host, port);
    }

    public Socket createSocket(Socket s, String host, int port, boolean autoClose) throws IOException {
        if (s == null) {
            throw new NullPointerException("the existing socket cannot be null");
        }
        return new SSLSocketImpl(s, host, port, autoClose, true);
    }

    public String[] getDefaultCipherSuites() {
        return Defaults.cipherSuites();
    }

    public String[] getSupportedCipherSuites() {
        return Defaults.cipherSuites();
    }
}
