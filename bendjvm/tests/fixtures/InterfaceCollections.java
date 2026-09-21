import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class InterfaceCollections {
    public static void main(String[] args) {
        List list = new ArrayList();
        list.add("a");
        System.out.println(list.size());
        System.out.println(list.contains("a"));
        Map map = new HashMap();
        map.put("k", "v");
        System.out.println(map.containsKey("k"));
        System.out.println(map.size());
    }
}
