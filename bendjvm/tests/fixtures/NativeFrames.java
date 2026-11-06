import java.io.FileInputStream;
import java.io.IOException;

// MiniJRE methods the VM implements appear as the innermost stack frame of the
// exceptions they raise (plan 05). Compiled with line numbers.
public class NativeFrames {
    static char at(String s, int i) {
        return s.charAt(i);
    }

    public static void main(String[] args) {
        try {
            at("abc", 10);
        } catch (StringIndexOutOfBoundsException e) {
            e.printStackTrace(System.out);
        }
        try {
            new FileInputStream("/definitely/missing/bendjvm-file");
        } catch (IOException e) {
            e.printStackTrace(System.out);
        }
        Thread.currentThread().interrupt();
        try {
            Thread.sleep(10);
        } catch (InterruptedException e) {
            e.printStackTrace(System.out);
        }
    }
}
