package javax.net.ssl;

import javax.net.ServerSocketFactory;

public abstract class SSLServerSocketFactory extends ServerSocketFactory {
    protected SSLServerSocketFactory() {
    }

    public static ServerSocketFactory getDefault() {
        return SSLContext.defaultContext().getServerSocketFactory();
    }

    public abstract String[] getDefaultCipherSuites();

    public abstract String[] getSupportedCipherSuites();
}
