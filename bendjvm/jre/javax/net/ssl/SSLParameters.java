package javax.net.ssl;

public class SSLParameters {
    private String[] cipherSuites;
    private String[] protocols;
    private boolean needClientAuth;
    private String identificationAlgorithm;

    public SSLParameters() {
    }

    public SSLParameters(String[] cipherSuites) {
        setCipherSuites(cipherSuites);
    }

    public SSLParameters(String[] cipherSuites, String[] protocols) {
        setCipherSuites(cipherSuites);
        setProtocols(protocols);
    }

    private static String[] copy(String[] values) {
        if (values == null) {
            return null;
        }
        String[] out = new String[values.length];
        System.arraycopy(values, 0, out, 0, values.length);
        return out;
    }

    public String[] getCipherSuites() {
        return copy(cipherSuites);
    }

    public void setCipherSuites(String[] cipherSuites) {
        this.cipherSuites = copy(cipherSuites);
    }

    public String[] getProtocols() {
        return copy(protocols);
    }

    public void setProtocols(String[] protocols) {
        this.protocols = copy(protocols);
    }

    public boolean getNeedClientAuth() {
        return needClientAuth;
    }

    public void setNeedClientAuth(boolean needClientAuth) {
        this.needClientAuth = needClientAuth;
    }

    public String getEndpointIdentificationAlgorithm() {
        return identificationAlgorithm;
    }

    public void setEndpointIdentificationAlgorithm(String algorithm) {
        this.identificationAlgorithm = algorithm;
    }
}
