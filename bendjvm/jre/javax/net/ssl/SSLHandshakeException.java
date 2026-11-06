package javax.net.ssl;

public class SSLHandshakeException extends SSLException {
    public SSLHandshakeException(String reason) {
        super(reason);
    }
}
