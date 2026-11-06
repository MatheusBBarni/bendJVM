package sun.security.ssl;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.BendSocketAccess;
import java.net.Socket;
import java.net.SocketException;
import javax.net.ssl.SSLException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import sun.nio.ch.HostIO;

/**
 * A TLS socket: Java owns its configuration, session view and stream API; the
 * host TLS provider owns the cryptographic state. The handshake runs on the
 * first I/O or startHandshake(); afterwards the socket's host handle is the
 * provider's TLS connection, so the inherited Socket streams carry plaintext.
 */
public final class SSLSocketImpl extends SSLSocket {
    private final Object handshakeLock = new Object();
    private final Socket layered;
    private final boolean autoClose;
    private final String peerHost;
    private final int peerPort;
    private boolean clientMode;
    private boolean needClientAuth;
    private String[] protocols = Defaults.protocols();
    private String[] suites = Defaults.cipherSuites();
    private String identification;
    private volatile SSLSessionImpl session;
    private boolean handshakeFailed;

    // A client connection over a new TCP socket (handshake deferred).
    SSLSocketImpl(String host, int port) throws IOException {
        super();
        connect(new java.net.InetSocketAddress(host, port));
        this.layered = null;
        this.autoClose = true;
        this.peerHost = host;
        this.peerPort = port;
        this.clientMode = true;
    }

    // TLS over an existing connected socket; the server side of an accepted one too.
    SSLSocketImpl(Socket socket, String host, int port, boolean autoClose, boolean clientMode) throws IOException {
        super();
        if (!socket.isConnected()) {
            throw new SocketException("Underlying socket is not connected");
        }
        BendSocketAccess.replaceHandle(this, BendSocketAccess.handle(socket));
        this.layered = socket;
        this.autoClose = autoClose;
        this.peerHost = host;
        this.peerPort = port;
        this.clientMode = clientMode;
    }

    public void startHandshake() throws IOException {
        synchronized (handshakeLock) {
            if (session != null) {
                return;
            }
            if (handshakeFailed || isClosed()) {
                throw new SocketException("Socket is closed");
            }
            StringBuilder settings = new StringBuilder();
            settings.append("host=").append(peerHost == null ? "" : peerHost).append('\n');
            settings.append("verifyHost=").append(clientMode && "HTTPS".equalsIgnoreCase(identification) ? "1" : "0").append('\n');
            settings.append("needClientAuth=").append(needClientAuth ? "1" : "0").append('\n');
            settings.append("protocols=").append(Defaults.join(protocols)).append('\n');
            settings.append("ciphers=").append(Defaults.join(suites)).append('\n');
            settings.append("timeout=").append(getSoTimeout()).append('\n');
            settings.append("autoClose=").append(layered == null || autoClose ? "1" : "0").append('\n');
            byte[] data = HostIO.utf8(settings.toString());
            int tls;
            try {
                tls = HostIO.call(HostIO.TLS_HANDSHAKE, BendSocketAccess.handle(this), clientMode ? 0 : 1, data, 0, data.length);
            } catch (IOException error) {
                handshakeFailed = true;
                closeQuietly();
                throw error;
            }
            BendSocketAccess.replaceHandle(this, tls);
            // With autoClose the layered socket shares the TLS connection;
            // without it, it keeps its own connection for after close().
            if (layered != null && autoClose) {
                BendSocketAccess.replaceHandle(layered, tls);
            }
            String protocol = HostIO.text(HostIO.TLS_INFO, tls, 0);
            String suite = HostIO.text(HostIO.TLS_INFO, tls, 1);
            session = new SSLSessionImpl(protocol, suite, peerHost, peerPort, true);
        }
    }

    private void closeQuietly() {
        try {
            close();
        } catch (IOException ignored) {
            // the handshake failure is what the caller sees
        }
    }

    public InputStream getInputStream() throws IOException {
        startHandshake();
        return super.getInputStream();
    }

    public OutputStream getOutputStream() throws IOException {
        startHandshake();
        return super.getOutputStream();
    }

    public SSLSession getSession() {
        try {
            startHandshake();
        } catch (IOException error) {
            return new SSLSessionImpl("NONE", "SSL_NULL_WITH_NULL_NULL", peerHost, peerPort, false);
        }
        return session;
    }

    public void close() throws IOException {
        SSLSessionImpl current = session;
        if (current != null) {
            current.invalidate();
        }
        if (layered != null && !autoClose) {
            // close_notify ends the TLS connection; the layered socket keeps
            // the TCP connection (the host hands it back after the TLS close).
            super.close();
            return;
        }
        super.close();
        if (layered != null) {
            layered.close();
        }
    }

    public String[] getSupportedCipherSuites() {
        return Defaults.cipherSuites();
    }

    public String[] getEnabledCipherSuites() {
        return Defaults.copy(suites);
    }

    public void setEnabledCipherSuites(String[] requested) {
        suites = Defaults.checked(requested, Defaults.cipherSuites(), "CipherSuite");
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

    public void setUseClientMode(boolean mode) {
        synchronized (handshakeLock) {
            if (session != null) {
                throw new IllegalArgumentException("Cannot change mode after SSL traffic has started");
            }
            clientMode = mode;
        }
    }

    public boolean getUseClientMode() {
        return clientMode;
    }

    public void setNeedClientAuth(boolean need) {
        needClientAuth = need;
    }

    public boolean getNeedClientAuth() {
        return needClientAuth;
    }

    public SSLParameters getSSLParameters() {
        SSLParameters parameters = super.getSSLParameters();
        parameters.setEndpointIdentificationAlgorithm(identification);
        return parameters;
    }

    public void setSSLParameters(SSLParameters params) {
        super.setSSLParameters(params);
        identification = params.getEndpointIdentificationAlgorithm();
        if (!params.getNeedClientAuth()) {
            needClientAuth = false;
        }
    }

    public String toString() {
        return "SSLSocket[" + (session == null ? "no handshake" : session.toString()) + ", " + super.toString() + "]";
    }
}
