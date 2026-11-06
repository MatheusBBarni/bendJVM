package fixture.resource;

import java.net.URL;
import java.util.Enumeration;

public class ResourceUrls {
    static final String[] NAMES = {
        "plain.txt",
        "with space.txt",
        "hash#percent%question?.txt",
        "reserved!$&'()*+,;=:@.txt",
        "brackets[]{}^`|\"<>~.txt",
        "café 中😀.txt",
        "nested dir/inner file.txt",
        "shared.txt",
    };

    public static void main(String[] args) throws Exception {
        ClassLoader loader = ResourceUrls.class.getClassLoader();
        String root = loader.getResource("fixture/resource/ResourceUrls.class").toString();
        String prefix = root.substring(0, root.length() - "fixture/resource/ResourceUrls.class".length());
        for (String name : NAMES) {
            Enumeration<URL> urls = loader.getResources(name);
            while (urls.hasMoreElements()) {
                URL url = urls.nextElement();
                String text = url.toString();
                System.out.println(name + " -> " + url.getProtocol() + " " + (text.startsWith(prefix) ? "<classes>" + text.substring(prefix.length()) : relative(text)));
                System.out.println("  path " + relative(url.getPath()) + " same " + text.equals(url.toExternalForm()));
            }
        }
    }

    // The jar's absolute location differs between machines; keep what follows its name.
    static String relative(String text) {
        int jar = text.indexOf("resources%20jar%20%c3%a9.jar");
        return jar < 0 ? text : "<jar>" + text.substring(jar);
    }
}
