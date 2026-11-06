package fixture.scan;

import java.io.File;
import java.io.InputStream;
import java.net.JarURLConnection;
import java.net.URI;
import java.net.URL;
import java.net.URLConnection;
import java.util.ArrayList;
import java.util.Enumeration;
import java.util.List;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;

// Component scanning the way Spring 5's PathMatchingResourcePatternResolver does
// it: package roots from ClassLoader.getResources, directory roots walked with
// File.listFiles, jar roots enumerated through JarURLConnection/JarFile, and each
// class read back through a relative URL's connection.
public class PackageScanning {
    public static void main(String[] args) throws Exception {
        ClassLoader loader = PackageScanning.class.getClassLoader();
        String[] roots = {"fixture/scan/", "fixture/scan/shared/", "fixture/scan/dir", "fixture/scan/missing/"};
        for (String root : roots) {
            Enumeration<URL> urls = loader.getResources(root);
            int count = 0;
            while (urls.hasMoreElements()) {
                URL url = urls.nextElement();
                count++;
                System.out.println(root + " -> " + url.getProtocol() + " " + tail(url.toString()));
                if (!root.endsWith("/")) {
                    continue;
                }
                if (url.getProtocol().equals("file")) {
                    scanDirectory(url);
                } else {
                    scanJar(url);
                }
            }
            System.out.println(root + " roots " + count);
        }
        System.out.println(File.separator + " " + File.separatorChar + " " + File.pathSeparator);
        URI uri = new URI("file:/tmp/with%20space/a%23b.txt");
        System.out.println(uri.getScheme() + " " + uri.getSchemeSpecificPart() + " " + uri.getPath() + " " + uri.getRawPath());
    }

    static String tail(String text) {
        int index = text.indexOf("fixture/scan");
        int jar = text.indexOf("scan%20jar.jar");
        return (jar >= 0 ? "<jar>" + text.substring(jar, jar + "scan%20jar.jar".length()) + " " : "") + text.substring(index);
    }

    static void scanDirectory(URL root) throws Exception {
        File directory = new File(root.toURI().getSchemeSpecificPart()).getAbsoluteFile();
        System.out.println("  dir " + directory.isDirectory() + " " + directory.getName() + " " + directory.exists());
        List<String> found = new ArrayList<String>();
        walk(directory, "", found);
        for (String name : sorted(found)) {
            URL entry = new URL(root, name);
            System.out.println("  " + name + " " + magic(entry.openConnection()));
        }
    }

    static void walk(File directory, String prefix, List<String> found) {
        File[] files = directory.listFiles();
        if (files == null) {
            return;
        }
        for (File file : files) {
            String name = prefix + file.getName();
            if (file.isDirectory()) {
                walk(file, name + "/", found);
            } else if (name.endsWith(".class")) {
                found.add(name);
            }
        }
    }

    static void scanJar(URL root) throws Exception {
        URLConnection connection = root.openConnection();
        JarURLConnection jarConnection = (JarURLConnection) connection;
        jarConnection.setUseCaches(false);
        JarFile jar = jarConnection.getJarFile();
        JarEntry rootEntry = jarConnection.getJarEntry();
        String rootPath = rootEntry != null ? rootEntry.getName() : "";
        System.out.println("  jar " + tail(jarConnection.getJarFileURL().toExternalForm() + "/fixture/scan") + " entry " + rootPath + " " + jarConnection.getEntryName());
        List<String> found = new ArrayList<String>();
        for (Enumeration<JarEntry> entries = jar.entries(); entries.hasMoreElements();) {
            JarEntry entry = entries.nextElement();
            String path = entry.getName();
            if (path.startsWith(rootPath) && path.endsWith(".class")) {
                found.add(path.substring(rootPath.length()));
            }
        }
        for (String name : sorted(found)) {
            JarEntry entry = jar.getJarEntry(rootPath + name);
            URL relative = new URL(root, name);
            System.out.println("  " + name + " " + entry.isDirectory() + " " + magic(relative.openConnection()) + " " + tail(relative.toString()));
        }
        jar.close();
    }

    static String magic(URLConnection connection) throws Exception {
        InputStream stream = connection.getInputStream();
        try {
            int a = stream.read(), b = stream.read(), c = stream.read(), d = stream.read();
            return Integer.toHexString(a) + Integer.toHexString(b) + Integer.toHexString(c) + Integer.toHexString(d);
        } finally {
            stream.close();
        }
    }

    // Insertion sort keeps the output independent of directory order.
    static List<String> sorted(List<String> values) {
        List<String> result = new ArrayList<String>();
        for (String value : values) {
            int index = 0;
            while (index < result.size() && result.get(index).compareTo(value) < 0) {
                index++;
            }
            result.add(index, value);
        }
        return result;
    }
}
