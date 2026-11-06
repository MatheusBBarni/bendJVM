package sun.security.ssl;

import javax.net.ssl.SSLSession;

final class SSLSessionImpl implements SSLSession {
    private final String protocol;
    private final String cipherSuite;
    private final String peerHost;
    private final int peerPort;
    private volatile boolean valid;

    SSLSessionImpl(String protocol, String cipherSuite, String peerHost, int peerPort, boolean valid) {
        this.protocol = protocol;
        this.cipherSuite = cipherSuite;
        this.peerHost = peerHost;
        this.peerPort = peerPort;
        this.valid = valid;
    }

    public String getProtocol() {
        return protocol;
    }

    public String getCipherSuite() {
        return cipherSuite;
    }

    public String getPeerHost() {
        return peerHost;
    }

    public int getPeerPort() {
        return peerPort;
    }

    public boolean isValid() {
        return valid;
    }

    public void invalidate() {
        valid = false;
    }

    public String toString() {
        return "Session(" + protocol + "|" + cipherSuite + ")";
    }
}
