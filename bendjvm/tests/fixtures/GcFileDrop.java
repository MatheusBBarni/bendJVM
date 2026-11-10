import java.io.FileInputStream;

public class GcFileDrop {
    public static void main(String[] args) throws Exception {
        FileInputStream in = new FileInputStream(args[0]);
        System.out.println(in.read());
        in = null;
        for (int i = 0; i < 1000; i++) {
            new Object();
        }
        System.out.println("done");
    }
}
