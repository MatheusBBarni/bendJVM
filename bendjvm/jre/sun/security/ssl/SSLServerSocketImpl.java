package sun.security.ssl;

import java.io.IOException;
import java.net.Socket;
import javax.net.ssl.SSLServerSocket;

/** Accepts TCP connections and returns server-mode TLS sockets (handshake deferred). */
public final class SSLServerSocketImpl extends SSLServerSocket {
    private boolean needClientAuth;
    private String[] protocols = Defaults.protocols();
    private String[] suites = Defaults.cipherSuites();

    SSLServerSocketImpl(int port) throws IOException {
        super(port);
    }

    public Socket accept() throws IOException {
        Socket plain = super.accept();
        SSLSocketImpl secure = new SSLSocketImpl(plain, null, plain.getPort(), true, false);
        secure.setNeedClientAuth(needClientAuth);
        secure.setEnabledProtocols(protocols);
        secure.setEnabledCipherSuites(suites);
        return secure;
    }

    public String[] getEnabledCipherSuites() {
        return Defaults.copy(suites);
    }

    public void setEnabledCipherSuites(String[] requested) {
        suites = Defaults.checked(requested, Defaults.cipherSuites(), "CipherSuite");
    }

    public String[] getSupportedCipherSuites() {
        return Defaults.cipherSuites();
    }

    public String[] getSupportedProtocols() {
        return Defaults.protocols();
    }

    public String[] getEnabledProtocols() {
        return Defaults.copy(protocols);
    }

    public void setEnabledProtocols(String[] requested) {
        protocols = Defaults.checked(requested, Defaults.protocols(), "protocol");
    }

    public void setNeedClientAuth(boolean need) {
        needClientAuth = need;
    }

    public boolean getNeedClientAuth() {
        return needClientAuth;
    }
}
