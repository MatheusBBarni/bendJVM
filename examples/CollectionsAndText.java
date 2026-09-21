import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class CollectionsAndText {
    public static void main(String[] args) {
        List names = new ArrayList();
        names.add("Bend");
        names.add("JVM");
        System.out.println((String) names.get(0) + (String) names.get(1));
        System.out.println(names.size());
        System.out.println(names.contains("Bend"));

        Map values = new HashMap();
        values.put("n", Integer.valueOf(2));
        System.out.println(((Integer) values.get("n")).intValue());
        System.out.println(Integer.valueOf(40) == Integer.valueOf(40));
        System.out.println(String.valueOf(true));
    }
}
