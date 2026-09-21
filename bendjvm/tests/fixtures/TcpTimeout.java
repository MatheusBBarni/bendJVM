import java.io.IOException;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;

public class TcpTimeout {
    public static void main(String[] args) throws Exception {
        ServerSocket server = new ServerSocket(0);
        Socket client = new Socket("127.0.0.1", server.getLocalPort());
        client.setSoTimeout(100);
        try {
            client.getInputStream().read();
            System.out.println("data");
        } catch (SocketTimeoutException error) {
            System.out.println("timeout");
        } catch (IOException error) {
            System.out.println("io");
        } finally {
            client.close();
            server.close();
        }
    }
}
