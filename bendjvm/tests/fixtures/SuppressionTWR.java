import java.io.IOException;

class CloseBoom implements AutoCloseable {
    private final String name;

    CloseBoom(String name) {
        this.name = name;
    }

    public void close() throws IOException {
        throw new IOException(name);
    }
}

public class SuppressionTWR {
    public static void main(String[] args) {
        try (CloseBoom first = new CloseBoom("first"); CloseBoom second = new CloseBoom("second")) {
            throw new IOException("primary");
        } catch (IOException error) {
            System.out.println(error.getMessage());
            Throwable[] suppressed = error.getSuppressed();
            System.out.println(suppressed.length);
            if (suppressed.length > 0) {
                System.out.println(suppressed[0].getMessage());
            }
            if (suppressed.length > 1) {
                System.out.println(suppressed[1].getMessage());
            }
        }
    }
}
