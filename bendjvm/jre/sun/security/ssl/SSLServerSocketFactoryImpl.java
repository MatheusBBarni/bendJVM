package sun.security.ssl;

import java.io.IOException;
import java.net.ServerSocket;
import javax.net.ssl.SSLServerSocketFactory;

public final class SSLServerSocketFactoryImpl extends SSLServerSocketFactory {
    public ServerSocket createServerSocket(int port) throws IOException {
        return new SSLServerSocketImpl(port);
    }

    public String[] getDefaultCipherSuites() {
        return Defaults.cipherSuites();
    }

    public String[] getSupportedCipherSuites() {
        return Defaults.cipherSuites();
    }
}
