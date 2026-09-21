package example.hello;

import example.lib.Answer;
import java.io.InputStream;

public class Main {
    public static void main(String[] args) throws Exception {
        if (args.length == 0) {
            System.out.println("hello");
        } else {
            System.out.println(args[0]);
        }
        System.out.println(Answer.value());
        InputStream stream = ClassLoader.getSystemResourceAsStream("banner.txt");
        if (stream == null) {
            System.out.println("missing");
            return;
        }
        System.out.println(stream.read());
        stream.close();
    }
}
