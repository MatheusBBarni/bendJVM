package javax.net.ssl;

import java.io.IOException;
import java.net.Socket;

public abstract class SSLSocket extends Socket {
    protected SSLSocket() {
        super();
    }

    public abstract String[] getSupportedCipherSuites();

    public abstract String[] getEnabledCipherSuites();

    public abstract void setEnabledCipherSuites(String[] suites);

    public abstract String[] getSupportedProtocols();

    public abstract String[] getEnabledProtocols();

    public abstract void setEnabledProtocols(String[] protocols);

    public abstract SSLSession getSession();

    public abstract void startHandshake() throws IOException;

    public abstract void setUseClientMode(boolean mode);

    public abstract boolean getUseClientMode();

    public abstract void setNeedClientAuth(boolean need);

    public abstract boolean getNeedClientAuth();

    public SSLParameters getSSLParameters() {
        SSLParameters parameters = new SSLParameters(getEnabledCipherSuites(), getEnabledProtocols());
        parameters.setNeedClientAuth(getNeedClientAuth());
        return parameters;
    }

    public void setSSLParameters(SSLParameters params) {
        if (params.getCipherSuites() != null) {
            setEnabledCipherSuites(params.getCipherSuites());
        }
        if (params.getProtocols() != null) {
            setEnabledProtocols(params.getProtocols());
        }
        if (params.getNeedClientAuth()) {
            setNeedClientAuth(true);
        }
    }
}
