import java.util.ArrayList;
import java.util.HashMap;

public class Collections {
    public static void main(String[] args) {
        ArrayList list = new ArrayList();
        list.add("a");
        list.add("b");
        System.out.println(list.size());
        System.out.println(list.contains("a"));
        System.out.println(list.isEmpty());
        list.clear();
        System.out.println(list.size());
        HashMap map = new HashMap();
        map.put("k", "v");
        System.out.println(map.size());
        System.out.println(map.containsKey("k"));
        System.out.println(map.isEmpty());
        map.clear();
        System.out.println(map.size());
    }
}
