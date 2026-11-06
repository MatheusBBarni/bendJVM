package isolated;

import java.io.ByteArrayInputStream;
import java.io.ObjectInputStream;

// Names no other isolated class, so a loader that defines only Reader meets
// Box first in the stream.
public class Reader {
    public static Object read(byte[] bytes) throws Exception {
        return new ObjectInputStream(new ByteArrayInputStream(bytes)).readObject();
    }
}
