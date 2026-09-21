import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;

public class FileRoundtrip {
    public static void main(String[] args) throws Exception {
        System.out.println("go");
        File file = new File("bendjvm-file-roundtrip.bin");
        System.out.println(file.getPath());
        FileOutputStream out = new FileOutputStream("bendjvm-file-roundtrip.bin");
        out.write(65);
        out.close();
        System.out.println(file.exists());
        FileInputStream in = new FileInputStream("bendjvm-file-roundtrip.bin");
        System.out.println(in.read());
        in.close();
    }
}
