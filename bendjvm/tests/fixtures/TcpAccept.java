import java.io.InputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;

public class TcpAccept {
    public static void main(String[] args) throws Exception {
        ServerSocket server = new ServerSocket(Integer.parseInt(args[0]));
        Socket socket = server.accept();
        InputStream in = socket.getInputStream();
        OutputStream out = socket.getOutputStream();
        int value = in.read();
        out.write(value + 1);
        out.flush();
        socket.close();
        server.close();
    }
}
