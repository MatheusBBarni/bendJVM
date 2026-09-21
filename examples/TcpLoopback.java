import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;

public class TcpLoopback {
    public static void main(String[] args) throws Exception {
        ServerSocket server = new ServerSocket(0);
        Socket client = new Socket("127.0.0.1", server.getLocalPort());
        Socket peer = server.accept();
        OutputStream outbound = client.getOutputStream();
        outbound.write(65);
        outbound.flush();
        int received = peer.getInputStream().read();
        OutputStream reply = peer.getOutputStream();
        reply.write(received + 1);
        reply.flush();
        InputStream inbound = client.getInputStream();
        System.out.println(inbound.read());
        System.out.println(server.getLocalPort() > 0);
        client.close();
        peer.close();
        server.close();
    }
}
