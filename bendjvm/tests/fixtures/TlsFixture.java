import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLHandshakeException;
import javax.net.ssl.SSLParameters;
import javax.net.ssl.SSLServerSocket;
import javax.net.ssl.SSLServerSocketFactory;
import javax.net.ssl.SSLSession;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

// TLS client/server sockets (plan 05). The trust store holds only the test CA;
// the identity is a CA-signed certificate for localhost/127.0.0.1. Run with:
//   TlsFixture <peer> <untrusted> <expired> <wrong-host> <serve-port>
// where the first four are ports of independent TLS peers and <serve-port> is
// where this program accepts two clients the harness connects (without and
// with a client certificate).
public class TlsFixture {
    static String readLine(InputStream in) throws IOException {
        StringBuilder line = new StringBuilder();
        int b;
        while ((b = in.read()) != -1 && b != '\n') {
            line.append((char) b);
        }
        return line.toString();
    }

    static SSLSocket open(String host, int port, boolean verifyHost) throws IOException {
        SSLSocket socket = (SSLSocket) SSLSocketFactory.getDefault().createSocket(host, port);
        if (verifyHost) {
            SSLParameters parameters = socket.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            socket.setSSLParameters(parameters);
        }
        return socket;
    }

    static String attempt(String host, int port, boolean verifyHost) {
        try {
            SSLSocket socket = open(host, port, verifyHost);
            try {
                socket.startHandshake();
                OutputStream out = socket.getOutputStream();
                out.write("ping\n".getBytes("UTF-8"));
                out.flush();
                return "connected, peer said " + readLine(socket.getInputStream());
            } finally {
                socket.close();
            }
        } catch (SSLHandshakeException expected) {
            return "rejected: " + expected.getClass().getName();
        } catch (IOException other) {
            return "failed: " + other.getClass().getName();
        }
    }

    public static void main(String[] args) throws Exception {
        int peer = Integer.parseInt(args[0]);
        int untrusted = Integer.parseInt(args[1]);
        int expired = Integer.parseInt(args[2]);
        int wrongHost = Integer.parseInt(args[3]);
        int servePort = Integer.parseInt(args[4]);

        // Java server and client in this VM: mutual authentication and endpoint identification.
        final SSLServerSocket server = (SSLServerSocket) SSLServerSocketFactory.getDefault().createServerSocket(0);
        server.setNeedClientAuth(true);
        System.out.println("server needs client auth: " + server.getNeedClientAuth());
        Thread serving = new Thread(new Runnable() {
            public void run() {
                try {
                    SSLSocket accepted = (SSLSocket) server.accept();
                    String line = readLine(accepted.getInputStream());
                    SSLSession session = accepted.getSession();
                    accepted.getOutputStream().write(("echo:" + line + " over " + session.getProtocol().startsWith("TLSv1.") + "\n").getBytes("UTF-8"));
                    accepted.close();
                } catch (IOException error) {
                    System.out.println("server error " + error);
                }
            }
        });
        serving.start();
        SSLSocket client = open("localhost", server.getLocalPort(), true);
        System.out.println("endpoint identification: " + client.getSSLParameters().getEndpointIdentificationAlgorithm());
        client.startHandshake();
        SSLSession session = client.getSession();
        System.out.println("protocol: " + session.getProtocol().startsWith("TLSv1.") + " suite: " + session.getCipherSuite().startsWith("TLS_")
            + " peer: " + session.getPeerHost() + " valid: " + session.isValid());
        client.getOutputStream().write("hello\n".getBytes("UTF-8"));
        InputStream in = client.getInputStream();
        System.out.println(readLine(in));
        System.out.println("after close_notify: " + in.read());
        client.close();
        serving.join();
        server.close();

        // Interoperability with an independent peer that requires client certificates.
        System.out.println("independent peer: " + attempt("localhost", peer, true));
        SSLSocket restricted = open("localhost", peer, true);
        restricted.setEnabledProtocols(new String[] {"TLSv1.2"});
        restricted.startHandshake();
        System.out.println("restricted protocol: " + restricted.getSession().getProtocol());
        restricted.close();
        SSLSocket defaults = open("localhost", peer, true);
        boolean obsolete = false;
        for (String protocol : defaults.getEnabledProtocols()) {
            obsolete |= protocol.equals("SSLv3") || protocol.equals("TLSv1") || protocol.equals("TLSv1.1");
        }
        System.out.println("obsolete protocols enabled by default: " + obsolete);
        try {
            defaults.setEnabledProtocols(new String[] {"TLSv9"});
        } catch (IllegalArgumentException expected) {
            System.out.println("unknown protocol refused: " + expected.getClass().getName());
        }
        defaults.close();

        // SSLContext factories, an explicit cipher suite, and the session's peer port.
        SSLContext context = SSLContext.getDefault();
        SSLSocket chosen = (SSLSocket) context.getSocketFactory().createSocket("localhost", peer);
        System.out.println("suites enabled: " + (chosen.getEnabledCipherSuites().length > 0) + " supported: " + (chosen.getSupportedCipherSuites().length > 0));
        chosen.setEnabledProtocols(new String[] {"TLSv1.2"});
        chosen.setEnabledCipherSuites(new String[] {"TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"});
        chosen.startHandshake();
        System.out.println("negotiated: " + chosen.getSession().getCipherSuite() + " peer port matches: " + (chosen.getSession().getPeerPort() == peer));
        chosen.close();
        final SSLServerSocket restrictedServer = (SSLServerSocket) context.getServerSocketFactory().createServerSocket(0);
        restrictedServer.setEnabledProtocols(new String[] {"TLSv1.2"});
        System.out.println("server protocols: " + restrictedServer.getEnabledProtocols().length + " " + restrictedServer.getEnabledProtocols()[0]
            + " suites: " + (restrictedServer.getEnabledCipherSuites().length > 0) + " need auth: " + restrictedServer.getNeedClientAuth());
        Thread restrictedServing = new Thread(new Runnable() {
            public void run() {
                try {
                    SSLSocket accepted = (SSLSocket) restrictedServer.accept();
                    accepted.getOutputStream().write((accepted.getSession().getProtocol() + "\n").getBytes("UTF-8"));
                    accepted.close();
                } catch (IOException error) {
                    System.out.println("restricted server error " + error);
                }
            }
        });
        restrictedServing.start();
        SSLSocket toRestricted = open("localhost", restrictedServer.getLocalPort(), true);
        System.out.println("server-restricted protocol: " + readLine(toRestricted.getInputStream()));
        toRestricted.close();
        restrictedServing.join();
        restrictedServer.close();

        // Layered TLS over a connected socket: autoClose decides who owns the connection.
        for (boolean autoClose : new boolean[] {false, true}) {
            Socket plain = new Socket("localhost", peer);
            SSLSocket layered = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(plain, "localhost", peer, autoClose);
            SSLParameters parameters = layered.getSSLParameters();
            parameters.setEndpointIdentificationAlgorithm("HTTPS");
            layered.setSSLParameters(parameters);
            layered.getOutputStream().write("ping\n".getBytes("UTF-8"));
            String reply = readLine(layered.getInputStream());
            layered.close();
            System.out.println("layered autoClose=" + autoClose + ": " + reply + ", plain closed " + plain.isClosed() + ", ssl closed " + layered.isClosed());
            plain.close();
        }

        // Certificate validation failures.
        System.out.println("untrusted: " + attempt("localhost", untrusted, true));
        System.out.println("expired: " + attempt("localhost", expired, true));
        System.out.println("wrong host, identification on: " + attempt("localhost", wrongHost, true));
        System.out.println("wrong host, identification off: " + attempt("localhost", wrongHost, false));

        // A stalled handshake times out on its own thread while another connection proceeds.
        final ServerSocket silent = new ServerSocket(0);
        final String[] stalled = new String[1];
        Thread staller = new Thread(new Runnable() {
            public void run() {
                try {
                    SSLSocket socket = open("localhost", silent.getLocalPort(), true);
                    socket.setSoTimeout(500);
                    socket.startHandshake();
                    stalled[0] = "handshake finished";
                } catch (SocketTimeoutException expected) {
                    stalled[0] = "stalled handshake: " + expected.getClass().getName();
                } catch (IOException other) {
                    stalled[0] = "stalled handshake: " + other.getClass().getName();
                }
            }
        });
        staller.start();
        Socket held = silent.accept();
        System.out.println("while stalled: " + attempt("localhost", peer, true));
        staller.join();
        System.out.println(stalled[0]);
        held.close();
        silent.close();

        // Clients the harness connects: first without a certificate, then with one.
        SSLServerSocket strict = (SSLServerSocket) SSLServerSocketFactory.getDefault().createServerSocket(servePort);
        strict.setNeedClientAuth(true);
        for (int i = 0; i < 2; i++) {
            SSLSocket accepted = (SSLSocket) strict.accept();
            try {
                accepted.startHandshake();
                String line = readLine(accepted.getInputStream());
                accepted.getOutputStream().write(("hi " + line + "\n").getBytes("UTF-8"));
                System.out.println("client " + i + ": authenticated, said " + line);
            } catch (SSLHandshakeException expected) {
                System.out.println("client " + i + ": rejected " + expected.getClass().getName());
            } catch (IOException other) {
                System.out.println("client " + i + ": failed " + other.getClass().getName());
            } finally {
                accepted.close();
            }
        }
        strict.close();
    }
}
