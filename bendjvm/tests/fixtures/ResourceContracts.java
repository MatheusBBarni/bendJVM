package fixture.resource;

import java.io.InputStream;
import java.io.IOException;
import java.net.URL;
import java.util.Dictionary;
import java.util.Enumeration;
import java.util.Hashtable;
import java.util.Map;
import java.util.Properties;

public class ResourceContracts {
    public static void main(String[] args) throws Exception {
        ClassLoader loader = ResourceContracts.class.getClassLoader();
        System.out.println(loader.getResource("missing") == null);
        System.out.println(loader.getResourceAsStream("missing") == null);
        System.out.println(!loader.getResources("missing").hasMoreElements());
        System.out.println(loader.getResource("/empty") == null);
        URL empty = loader.getResource("empty");
        try (InputStream stream = empty.openStream()) {
            System.out.println(stream.read());
        }
        Enumeration<URL> resources = loader.getResources("duplicate");
        URL first = resources.nextElement();
        URL second = resources.nextElement();
        System.out.println(!resources.hasMoreElements());
        InputStream one = first.openStream();
        InputStream independent = first.openStream();
        InputStream two = second.openStream();
        System.out.println(one.read());
        System.out.println(one.read());
        System.out.println(independent.read());
        System.out.println(two.read());
        one.close(); independent.close(); two.close();
        try { one.read(); System.out.println(false); }
        catch (IOException closed) { System.out.println(true); }
        Properties properties = new Properties();
        System.out.println(properties instanceof Hashtable);
        System.out.println(properties instanceof Dictionary);
        System.out.println(properties instanceof Map);
        Map map = properties;
        map.put("name", "first");
        System.out.println(properties.setProperty("name", "second"));
        System.out.println(properties.getProperty("name"));
        System.out.println(map.size());
        map.remove("name");
        System.out.println(properties.getProperty("name", "missing"));
    }
}
