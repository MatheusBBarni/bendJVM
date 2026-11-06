package isolated;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.ObjectOutputStream;

public class Serial {
    public static byte[] boxBytes() throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        ObjectOutputStream out = new ObjectOutputStream(bytes);
        out.writeObject(new Box<String>("boxed"));
        out.close();
        return bytes.toByteArray();
    }

    public static String roundTrip() throws Exception {
        Object value = Reader.read(boxBytes());
        return value.getClass().getName() + " " + (value.getClass() == Box.class) + " " + ((Box<?>) value).label;
    }
}
