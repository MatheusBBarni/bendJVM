package javax.net.ssl;

public class SSLPeerUnverifiedException extends SSLException {
    public SSLPeerUnverifiedException(String reason) {
        super(reason);
    }
}
