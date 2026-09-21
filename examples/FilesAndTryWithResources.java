import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;

public class FilesAndTryWithResources {
    public static void main(String[] args) throws Exception {
        String path = args.length > 0 ? args[0] : "bendjvm-example.bin";
        File file = new File(path);
        FileOutputStream out = new FileOutputStream(file.getPath());
        out.write(65);
        out.close();
        System.out.println(file.exists());

        try (FileInputStream in = new FileInputStream(file.getPath())) {
            System.out.println(in.read());
        }

        BufferedReader reader = new BufferedReader(
            new InputStreamReader(new ByteArrayInputStream(new byte[] {'h', 'i', '\n', 'o', 'k'}), "UTF-8"));
        System.out.println(reader.readLine());
        reader.close();

        int recovered = 0;
        try (FileInputStream closed = new FileInputStream(file.getPath())) {
            closed.close();
            recovered = closed.read();
        } catch (IOException error) {
            recovered = -2;
        }
        System.out.println(recovered);
    }
}
