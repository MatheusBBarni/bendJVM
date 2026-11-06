package javax.net.ssl;

public interface SSLSession {
    String getProtocol();

    String getCipherSuite();

    String getPeerHost();

    int getPeerPort();

    boolean isValid();

    void invalidate();
}
