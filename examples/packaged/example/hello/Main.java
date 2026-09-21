package example.hello;

import example.lib.Answer;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

public class Main {
    public static void main(String[] args) throws Exception {
        List parts = new ArrayList();
        if (args.length == 0) {
            parts.add("hello");
        } else {
            parts.add(args[0]);
        }
        parts.add(String.valueOf(Answer.value()));
        System.out.println((String) parts.get(0));
        System.out.println((String) parts.get(1));

        InputStream stream = ClassLoader.getSystemResourceAsStream("banner.txt");
        if (stream == null) {
            System.out.println("missing");
            return;
        }
        try {
            System.out.println(stream.read());
        } finally {
            stream.close();
        }
    }
}
