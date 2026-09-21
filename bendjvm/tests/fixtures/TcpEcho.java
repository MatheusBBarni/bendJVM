import java.io.InputStream;
import java.io.OutputStream;
import java.net.Socket;

public class TcpEcho {
    public static void main(String[] args) throws Exception {
        Socket socket = new Socket("127.0.0.1", Integer.parseInt(args[0]));
        OutputStream out = socket.getOutputStream();
        InputStream in = socket.getInputStream();
        out.write(65);
        out.flush();
        System.out.println(in.read());
        socket.close();
    }
}
