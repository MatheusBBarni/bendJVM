package javax.net.ssl;

import java.security.NoSuchAlgorithmException;

/**
 * The fixed TLS provider context: trust roots and key material come from the
 * launcher (--tls-trust, --tls-key, --tls-cert), never from Java code.
 * Dynamic init with custom KeyManagers/TrustManagers is outside the MiniJRE.
 */
public class SSLContext {
    private static SSLContext defaultContext;
    private final String protocol;

    private SSLContext(String protocol) {
        this.protocol = protocol;
    }

    static synchronized SSLContext defaultContext() {
        if (defaultContext == null) {
            defaultContext = new SSLContext("Default");
        }
        return defaultContext;
    }

    public static SSLContext getDefault() throws NoSuchAlgorithmException {
        return defaultContext();
    }

    public static SSLContext getInstance(String protocol) throws NoSuchAlgorithmException {
        if (protocol == null) {
            throw new NullPointerException("null protocol name");
        }
        if (!protocol.equals("TLS") && !protocol.equals("TLSv1.2") && !protocol.equals("TLSv1.3") && !protocol.equals("Default")) {
            throw new NoSuchAlgorithmException(protocol + " SSLContext not available");
        }
        return defaultContext();
    }

    public final String getProtocol() {
        return protocol;
    }

    public final SSLSocketFactory getSocketFactory() {
        return new sun.security.ssl.SSLSocketFactoryImpl();
    }

    public final SSLServerSocketFactory getServerSocketFactory() {
        return new sun.security.ssl.SSLServerSocketFactoryImpl();
    }

    public final SSLParameters getDefaultSSLParameters() {
        return new SSLParameters(sun.security.ssl.Defaults.cipherSuites(), sun.security.ssl.Defaults.protocols());
    }
}
