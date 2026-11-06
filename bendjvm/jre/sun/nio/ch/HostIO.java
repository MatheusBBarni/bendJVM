package sun.nio.ch;

import java.io.IOException;

/**
 * The single host-effect gateway of the Java-source networking classes (plan 05).
 *
 * {@link #call} parks only the calling Java thread while the host performs
 * operation {@code op}; it sends {@code data[off, off+len)} and receives the
 * host's reply bytes into the same range. Host failures arrive as the Java
 * exception the host names. The op codes are shared with scripts/run.py.
 */
public final class HostIO {
    public static final int CONNECT = 1;
    public static final int FINISH_CONNECT = 2;
    public static final int READ = 3;
    public static final int WRITE = 4;
    public static final int SHUTDOWN = 5;
    public static final int CLOSE = 6;
    public static final int LISTEN = 7;
    public static final int ACCEPT = 8;
    public static final int LOCAL_PORT = 9;
    public static final int REMOTE_PORT = 10;
    public static final int SELECT = 12;
    public static final int WAKEUP = 11;
    public static final int TLS_HANDSHAKE = 13;
    public static final int TLS_INFO = 14;
    public static final int TLS_DEFAULTS = 15;
    public static final int REMOTE_HOST = 16;
    public static final int RESOLVE = 17;

    /** arg flag: return at once instead of waiting (non-blocking channels, selectNow). */
    public static final int NONBLOCKING = 1 << 29;
    /** arg flag: an interrupt of the calling thread ends the wait (NIO semantics). */
    public static final int INTERRUPTIBLE = 1 << 30;
    /** Largest timeout in milliseconds an arg carries; also "no timeout". */
    public static final int FOREVER = (1 << 29) - 1;

    private HostIO() {
    }

    public static native int call(int op, int handle, int arg, byte[] data, int off, int len) throws IOException;

    public static int call(int op, int handle, int arg) throws IOException {
        return call(op, handle, arg, null, 0, 0);
    }

    public static int timeoutArg(int millis) {
        return millis <= 0 || millis > FOREVER ? FOREVER : millis;
    }

    public static byte[] utf8(String text) {
        int size = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            size += c < 0x80 ? 1 : c < 0x800 ? 2 : 3;
        }
        byte[] out = new byte[size];
        int p = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c < 0x80) {
                out[p++] = (byte) c;
            } else if (c < 0x800) {
                out[p++] = (byte) (0xC0 | (c >> 6));
                out[p++] = (byte) (0x80 | (c & 0x3F));
            } else {
                out[p++] = (byte) (0xE0 | (c >> 12));
                out[p++] = (byte) (0x80 | ((c >> 6) & 0x3F));
                out[p++] = (byte) (0x80 | (c & 0x3F));
            }
        }
        return out;
    }

    /** Decodes UTF-8 produced by the host (BMP characters). */
    public static String string(byte[] data, int len) {
        StringBuilder text = new StringBuilder();
        int i = 0;
        while (i < len) {
            int b = data[i] & 0xFF;
            if (b < 0x80) {
                text.append((char) b);
                i += 1;
            } else if (b < 0xE0) {
                text.append((char) (((b & 0x1F) << 6) | (data[i + 1] & 0x3F)));
                i += 2;
            } else {
                text.append((char) (((b & 0x0F) << 12) | ((data[i + 1] & 0x3F) << 6) | (data[i + 2] & 0x3F)));
                i += 3;
            }
        }
        return text.toString();
    }

    /** A host operation answering with text (TLS details, peer names). */
    public static String text(int op, int handle, int arg) throws IOException {
        byte[] data = new byte[1024];
        int n = call(op, handle, arg, data, 0, data.length);
        return n < 0 ? null : string(data, n);
    }

    public static int connect(String host, int port, int timeoutMillis, int flags) throws IOException {
        byte[] name = utf8(host);
        return call(CONNECT, timeoutArg(timeoutMillis), port | flags, name, 0, name.length);
    }
}
