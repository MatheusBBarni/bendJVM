import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;

public class MemoryStreams {
    public static void main(String[] args) throws Exception {
        byte[] src = new byte[] { 10, 20, 30 };
        ByteArrayInputStream in = new ByteArrayInputStream(src);
        System.out.println(in.read());
        System.out.println(in.read());
        System.out.println(in.read());
        in.close();
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.write(7);
        out.write(8);
        System.out.println(out.size());
        byte[] all = out.toByteArray();
        System.out.println((int) all[0]);
        System.out.println((int) all[1]);
        out.reset();
        System.out.println(out.size());
        out.close();
    }
}
