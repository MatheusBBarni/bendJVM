package fixture.resource;

import java.io.InputStream;

public class ResourceConsumer {
    public static void main(String[] args) throws Exception {
        InputStream stream = ClassLoader.getSystemResourceAsStream("fixture-resource.bin");
        if (stream == null) {
            System.out.println("missing");
            return;
        }
        int first = stream.read();
        int second = stream.read();
        int third = stream.read();
        int fourth = stream.read();
        int fifth = stream.read();
        stream.close();
        System.out.println(first);
        System.out.println(second);
        System.out.println(third);
        System.out.println(fourth);
        System.out.println(fifth);
    }
}
