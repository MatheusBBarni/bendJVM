import java.io.IOException;
import java.net.ConnectException;
import java.net.Socket;

public class TcpRefused {
    public static void main(String[] args) {
        try {
            new Socket("127.0.0.1", 1);
            System.out.println("connected");
        } catch (ConnectException error) {
            System.out.println("refused");
        } catch (IOException error) {
            System.out.println("io");
        }
    }
}
