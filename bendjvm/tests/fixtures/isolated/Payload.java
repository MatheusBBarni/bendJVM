package isolated;

public class Payload {
    public static int initialized;

    static {
        initialized++;
    }

    public String run() {
        return "payload " + new Helper().value() + " " + initialized;
    }

    public ClassLoader loader() {
        return Payload.class.getClassLoader();
    }
}
