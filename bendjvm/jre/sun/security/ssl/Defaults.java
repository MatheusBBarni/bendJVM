package sun.security.ssl;

import java.io.IOException;
import sun.nio.ch.HostIO;

/** The provider's supported protocols and cipher suites (Java names). */
public final class Defaults {
    private static String[] protocols;
    private static String[] suites;

    private Defaults() {
    }

    static String[] split(String text) {
        int count = text.length() == 0 ? 0 : 1;
        for (int i = 0; i < text.length(); i++) {
            if (text.charAt(i) == ',') {
                count++;
            }
        }
        String[] parts = new String[count];
        int start = 0;
        int index = 0;
        for (int i = 0; i <= text.length() && count > 0; i++) {
            if (i == text.length() || text.charAt(i) == ',') {
                parts[index++] = text.substring(start, i);
                start = i + 1;
            }
        }
        return parts;
    }

    static String join(String[] values) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < values.length; i++) {
            if (i > 0) {
                text.append(',');
            }
            text.append(values[i]);
        }
        return text.toString();
    }

    static String[] copy(String[] values) {
        String[] out = new String[values.length];
        System.arraycopy(values, 0, out, 0, values.length);
        return out;
    }

    public static synchronized String[] protocols() {
        if (protocols == null) {
            protocols = query(0);
        }
        return copy(protocols);
    }

    public static synchronized String[] cipherSuites() {
        if (suites == null) {
            suites = query(1);
        }
        return copy(suites);
    }

    private static String[] query(int what) {
        try {
            return split(HostIO.text(HostIO.TLS_DEFAULTS, 0, what));
        } catch (IOException error) {
            return new String[0];
        }
    }

    static String[] checked(String[] requested, String[] supported, String kind) {
        if (requested == null) {
            throw new IllegalArgumentException(kind + " cannot be null");
        }
        for (String value : requested) {
            boolean known = false;
            for (String option : supported) {
                known |= option.equals(value);
            }
            if (!known) {
                throw new IllegalArgumentException("Unsupported " + kind + ": " + value);
            }
        }
        return copy(requested);
    }
}
