import java.io.ByteArrayInputStream;

public class TryWithResources {
    public static void main(String[] args) throws Exception {
        try (ByteArrayInputStream in = new ByteArrayInputStream(new byte[] { 7, 8 })) {
            System.out.println(in.read());
            System.out.println(in.read());
        }
        System.out.println("done");
    }
}
