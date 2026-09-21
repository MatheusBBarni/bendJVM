import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.Socket;
import java.util.ArrayList;

public class RuntimeExpansionApp {
    public static void main(String[] args) throws Exception {
        InputStream resource = ClassLoader.getSystemResourceAsStream("fixture-resource.bin");
        int marker = resource.read();
        resource.close();

        ArrayList items = new ArrayList();
        items.add("ok");
        String text = String.valueOf(marker) + (String) items.get(0);

        FileOutputStream out = new FileOutputStream(args[0]);
        out.write(65);
        out.close();
        FileInputStream in = new FileInputStream(args[0]);
        int copied = in.read();
        in.close();

        Socket socket = new Socket("127.0.0.1", Integer.parseInt(args[1]));
        socket.getOutputStream().write(66);
        socket.getOutputStream().flush();
        int echoed = socket.getInputStream().read();
        socket.close();

        int recovered = 0;
        try (FileInputStream closed = new FileInputStream(args[0])) {
            closed.close();
            recovered = closed.read();
        } catch (IOException error) {
            recovered = -2;
        }

        System.out.println(text);
        System.out.println(copied);
        System.out.println(echoed);
        System.out.println(recovered);
    }
}
