package java.net;

import java.io.IOException;
import sun.nio.ch.HostIO;

/**
 * An IP address with an optional host name. Names resolve on the host (DNS
 * runs outside the interpreter and parks only the calling thread); literal
 * addresses are taken as they are.
 */
public class InetAddress implements java.io.Serializable {
    private final String hostName;
    private final String address;

    InetAddress(String hostName, String address) {
        this.hostName = hostName;
        this.address = address;
    }

    static boolean isLiteral(String host) {
        if (host.indexOf(':') >= 0) {
            return true;
        }
        int parts = 0;
        int digits = 0;
        for (int i = 0; i < host.length(); i++) {
            char c = host.charAt(i);
            if (c == '.') {
                if (digits == 0) {
                    return false;
                }
                parts++;
                digits = 0;
            } else if (c >= '0' && c <= '9' && digits < 3) {
                digits++;
            } else {
                return false;
            }
        }
        return parts == 3 && digits > 0;
    }

    public static InetAddress getByName(String host) throws UnknownHostException {
        if (host == null || host.length() == 0) {
            return getLoopbackAddress();
        }
        if (host.startsWith("[") && host.endsWith("]")) {
            host = host.substring(1, host.length() - 1);
        }
        if (isLiteral(host)) {
            return new InetAddress(null, host);
        }
        byte[] name = HostIO.utf8(host);
        byte[] reply = new byte[Math.max(64, name.length)];
        System.arraycopy(name, 0, reply, 0, name.length);
        int n;
        try {
            n = HostIO.call(HostIO.RESOLVE, 0, name.length, reply, 0, reply.length);
        } catch (UnknownHostException unknown) {
            throw unknown;
        } catch (IOException other) {
            throw new UnknownHostException(host);
        }
        return new InetAddress(host, HostIO.string(reply, n));
    }

    public static InetAddress getLoopbackAddress() {
        return new InetAddress("localhost", "127.0.0.1");
    }

    static InetAddress anyLocal() {
        return new InetAddress("0.0.0.0", "0.0.0.0");
    }

    public String getHostName() {
        return hostName != null ? hostName : address;
    }

    public String getHostAddress() {
        return address;
    }

    public byte[] getAddress() {
        if (address.indexOf(':') < 0) {
            byte[] bytes = new byte[4];
            int part = 0;
            int value = 0;
            for (int i = 0; i <= address.length(); i++) {
                if (i == address.length() || address.charAt(i) == '.') {
                    bytes[part++] = (byte) value;
                    value = 0;
                } else {
                    value = value * 10 + (address.charAt(i) - '0');
                }
            }
            return bytes;
        }
        return ipv6Bytes(address);
    }

    private static byte[] ipv6Bytes(String text) {
        byte[] bytes = new byte[16];
        int gap = text.indexOf("::");
        String head = gap < 0 ? text : text.substring(0, gap);
        String tail = gap < 0 ? "" : text.substring(gap + 2);
        int[] front = groups(head);
        int[] back = groups(tail);
        for (int i = 0; i < front.length; i++) {
            bytes[2 * i] = (byte) (front[i] >> 8);
            bytes[2 * i + 1] = (byte) front[i];
        }
        for (int i = 0; i < back.length; i++) {
            int at = 8 - back.length + i;
            bytes[2 * at] = (byte) (back[i] >> 8);
            bytes[2 * at + 1] = (byte) back[i];
        }
        return bytes;
    }

    private static int[] groups(String text) {
        if (text.length() == 0) {
            return new int[0];
        }
        int count = 1;
        for (int i = 0; i < text.length(); i++) {
            if (text.charAt(i) == ':') {
                count++;
            }
        }
        int[] values = new int[count];
        int index = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == ':') {
                index++;
            } else {
                int digit = c <= '9' ? c - '0' : (c | 0x20) - 'a' + 10;
                values[index] = values[index] * 16 + digit;
            }
        }
        return values;
    }

    public boolean isLoopbackAddress() {
        return address.startsWith("127.") || address.equals("::1");
    }

    public boolean isAnyLocalAddress() {
        return address.equals("0.0.0.0") || address.equals("::");
    }

    public boolean equals(Object other) {
        return other instanceof InetAddress && ((InetAddress) other).address.equals(address);
    }

    public int hashCode() {
        return address.hashCode();
    }

    public String toString() {
        return (hostName != null ? hostName : "") + "/" + address;
    }
}
