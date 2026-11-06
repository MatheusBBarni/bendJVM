import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.UnknownHostException;
import java.nio.channels.SocketChannel;
import java.nio.channels.UnresolvedAddressException;

// Name resolution for InetAddress and InetSocketAddress (plan 05).
public class NetAddresses {
    public static void main(String[] args) throws Exception {
        InetAddress literal = InetAddress.getByName("127.0.0.1");
        System.out.println("literal: " + literal + " host " + literal.getHostAddress() + " loopback " + literal.isLoopbackAddress());
        byte[] bytes = literal.getAddress();
        System.out.println("bytes: " + bytes.length + " " + bytes[0] + "." + bytes[3]);
        InetAddress local = InetAddress.getByName("localhost");
        System.out.println("localhost: " + local);
        System.out.println("loopback: " + InetAddress.getLoopbackAddress());
        System.out.println("equal: " + literal.equals(local));
        try {
            InetAddress.getByName("no-such-host.invalid");
            System.out.println("resolved?");
        } catch (UnknownHostException expected) {
            System.out.println("unknown host: " + expected.getClass().getName());
        }

        InetSocketAddress resolved = new InetSocketAddress("localhost", 8080);
        System.out.println("socket address: " + resolved + " unresolved " + resolved.isUnresolved() + " host " + resolved.getHostString());
        InetSocketAddress missing = new InetSocketAddress("no-such-host.invalid", 80);
        System.out.println("missing unresolved: " + missing.isUnresolved() + " address " + missing.getAddress());
        InetSocketAddress unresolved = InetSocketAddress.createUnresolved("localhost", 9);
        System.out.println("createUnresolved: " + unresolved.isUnresolved());
        System.out.println("wildcard: " + new InetSocketAddress(0).getAddress().isAnyLocalAddress());
        try {
            new Socket().connect(missing);
        } catch (UnknownHostException expected) {
            System.out.println("socket connect: " + expected.getClass().getName() + " " + expected.getMessage());
        }
        try {
            SocketChannel.open().connect(missing);
        } catch (UnresolvedAddressException expected) {
            System.out.println("channel connect: " + expected.getClass().getName());
        }
    }
}
