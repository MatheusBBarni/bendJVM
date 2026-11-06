package javax.net.ssl;

import java.io.IOException;
import java.net.ServerSocket;

public abstract class SSLServerSocket extends ServerSocket {
    protected SSLServerSocket(int port) throws IOException {
        super(port);
    }

    public abstract String[] getEnabledCipherSuites();

    public abstract void setEnabledCipherSuites(String[] suites);

    public abstract String[] getSupportedCipherSuites();

    public abstract String[] getSupportedProtocols();

    public abstract String[] getEnabledProtocols();

    public abstract void setEnabledProtocols(String[] protocols);

    public abstract void setNeedClientAuth(boolean need);

    public abstract boolean getNeedClientAuth();
}
