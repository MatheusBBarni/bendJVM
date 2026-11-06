package isolated;

import java.io.Serializable;
import java.util.List;

@Tag("box")
public class Box<T> implements Serializable {
    private static final long serialVersionUID = 1L;
    public String label;
    public List<Helper> helpers;

    public Box(String label) {
        this.label = label;
    }
}
