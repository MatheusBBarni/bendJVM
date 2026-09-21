import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.InputStreamReader;

public class LineReader {
    public static void main(String[] args) throws Exception {
        byte[] data = new byte[] { 'h', 'i', '\n', 't', 'o' };
        BufferedReader reader = new BufferedReader(new InputStreamReader(new ByteArrayInputStream(data), "UTF-8"));
        System.out.println(reader.readLine());
        System.out.println(reader.readLine());
        System.out.println(reader.readLine() == null);
        reader.close();
    }
}
