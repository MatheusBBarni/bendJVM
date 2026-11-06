import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.BufferOverflowException;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.nio.channels.CancelledKeyException;
import java.nio.channels.ClosedByInterruptException;
import java.nio.channels.ClosedChannelException;
import java.nio.channels.ClosedSelectorException;
import java.nio.channels.IllegalBlockingModeException;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.nio.channels.ServerSocketChannel;
import java.nio.channels.SocketChannel;
import java.util.Iterator;

// ByteBuffer semantics and a non-blocking echo server driven by a Selector (plan 05).
public class NioSelectorEcho {
    static volatile boolean stop;

    public static void main(String[] args) throws Exception {
        buffers();
        final Selector selector = Selector.open();
        final ServerSocketChannel server = ServerSocketChannel.open();
        server.bind(new InetSocketAddress("127.0.0.1", 0));
        try {
            server.register(selector, SelectionKey.OP_ACCEPT);
        } catch (IllegalBlockingModeException expected) {
            System.out.println("register blocking: " + expected.getClass().getName());
        }
        server.configureBlocking(false);
        System.out.println("non-blocking accept with no client: " + server.accept());
        SelectionKey serverKey = server.register(selector, SelectionKey.OP_ACCEPT);
        System.out.println("valid ops: " + server.validOps() + " interest: " + serverKey.interestOps());
        final int port = ((InetSocketAddress) server.getLocalAddress()).getPort();

        Thread loop = new Thread(new Runnable() {
            public void run() {
                try {
                    echoLoop(selector);
                } catch (IOException error) {
                    System.out.println("loop error " + error);
                }
            }
        });
        loop.start();

        // Two blocking clients; their messages arrive in pieces.
        SocketChannel first = SocketChannel.open(new InetSocketAddress("127.0.0.1", port));
        SocketChannel second = SocketChannel.open(new InetSocketAddress("127.0.0.1", port));
        System.out.println("connected: " + first.isConnected() + " blocking: " + first.isBlocking());
        System.out.println(roundTrip(first, "hello"));
        System.out.println(roundTrip(second, "world"));
        System.out.println(roundTrip(first, "again"));

        // A non-blocking client: connect, finishConnect, zero-byte read.
        SocketChannel third = SocketChannel.open();
        third.configureBlocking(false);
        third.connect(new InetSocketAddress("127.0.0.1", port));
        while (!third.finishConnect()) {
            Thread.yield();
        }
        ByteBuffer empty = ByteBuffer.allocate(8);
        System.out.println("non-blocking read with no data: " + third.read(empty) + " position " + empty.position());
        third.close();
        try {
            third.read(empty);
        } catch (ClosedChannelException expected) {
            System.out.println("read after close: " + expected.getClass().getName());
        }

        // wakeup ends a blocking select from another thread.
        final Selector idle = Selector.open();
        final int[] selected = {-1};
        Thread sleeper = new Thread(new Runnable() {
            public void run() {
                try {
                    selected[0] = idle.select();
                } catch (IOException error) {
                    System.out.println("select error " + error);
                }
            }
        });
        sleeper.start();
        settle();
        // A wakeup before or during select() ends it (JDK Selector.wakeup).
        idle.wakeup();
        sleeper.join();
        System.out.println("woken select returned " + selected[0]);
        System.out.println("pending wakeup makes selectNow return: " + idle.wakeup().select(1000));

        // An interrupted select returns at once and keeps the interrupt status.
        Thread interrupted = new Thread(new Runnable() {
            public void run() {
                try {
                    int n = idle.select();
                    System.out.println("interrupted select returned " + n + " flag " + Thread.currentThread().isInterrupted());
                } catch (IOException error) {
                    System.out.println("select error " + error);
                }
            }
        });
        interrupted.start();
        settle();
        interrupted.interrupt();
        interrupted.join();
        idle.close();
        try {
            idle.select();
        } catch (ClosedSelectorException expected) {
            System.out.println("select on closed selector: " + expected.getClass().getName());
        }

        // An interrupted blocking channel read closes the channel.
        final SocketChannel blocked = SocketChannel.open(new InetSocketAddress("127.0.0.1", port));
        Thread channelReader = new Thread(new Runnable() {
            public void run() {
                try {
                    blocked.read(ByteBuffer.allocate(4));
                    System.out.println("read returned");
                } catch (ClosedByInterruptException expected) {
                    System.out.println("interrupted read: " + expected.getClass().getName() + " open " + blocked.isOpen()
                        + " flag " + Thread.currentThread().isInterrupted());
                } catch (IOException other) {
                    System.out.println("interrupted read: " + other);
                }
            }
        });
        channelReader.start();
        settle();
        channelReader.interrupt();
        channelReader.join();

        // Cancelled keys stop being selected.
        serverKey.cancel();
        try {
            serverKey.interestOps();
        } catch (CancelledKeyException expected) {
            System.out.println("cancelled key: " + expected.getClass().getName() + " valid " + serverKey.isValid());
        }

        first.close();
        second.close();
        stop = true;
        selector.wakeup();
        loop.join();
        selector.close();
        server.close();
        System.out.println("server open: " + server.isOpen() + " selector open: " + selector.isOpen());
    }

    // Gives other threads a chance to block; results do not depend on it.
    static void settle() {
        for (int i = 0; i < 2000; i++) {
            Thread.yield();
        }
    }

    static String roundTrip(SocketChannel channel, String text) throws IOException {
        byte[] bytes = text.getBytes("UTF-8");
        ByteBuffer out = ByteBuffer.wrap(bytes);
        while (out.hasRemaining()) {
            channel.write(out);
        }
        ByteBuffer in = ByteBuffer.allocate(bytes.length);
        while (in.hasRemaining()) {
            if (channel.read(in) < 0) {
                break;
            }
        }
        in.flip();
        byte[] got = new byte[in.remaining()];
        in.get(got);
        return "echoed " + new String(got, "UTF-8");
    }

    static void echoLoop(Selector selector) throws IOException {
        ByteBuffer buffer = ByteBuffer.allocate(3);
        while (!stop) {
            selector.select();
            Iterator<SelectionKey> keys = selector.selectedKeys().iterator();
            while (keys.hasNext()) {
                SelectionKey key = keys.next();
                keys.remove();
                if (!key.isValid()) {
                    continue;
                }
                if (key.isAcceptable()) {
                    SocketChannel client = ((ServerSocketChannel) key.channel()).accept();
                    if (client != null) {
                        client.configureBlocking(false);
                        client.register(selector, SelectionKey.OP_READ);
                    }
                } else if (key.isReadable()) {
                    SocketChannel client = (SocketChannel) key.channel();
                    buffer.clear();
                    int n = client.read(buffer);
                    if (n < 0) {
                        key.cancel();
                        client.close();
                        continue;
                    }
                    buffer.flip();
                    while (buffer.hasRemaining()) {
                        client.write(buffer);
                    }
                }
            }
        }
    }

    static void buffers() {
        ByteBuffer buffer = ByteBuffer.allocate(8);
        System.out.println(buffer);
        buffer.put((byte) 1).put((byte) 2).put(new byte[] {3, 4, 5});
        System.out.println("after puts: position " + buffer.position() + " remaining " + buffer.remaining());
        buffer.flip();
        System.out.println("flipped: limit " + buffer.limit() + " get " + buffer.get() + " index 3 " + buffer.get(3));
        byte[] dst = new byte[2];
        buffer.get(dst);
        System.out.println("bulk get: " + dst[0] + "," + dst[1] + " position " + buffer.position());
        try {
            buffer.get(new byte[5]);
        } catch (BufferUnderflowException expected) {
            System.out.println("underflow keeps position " + buffer.position());
        }
        buffer.compact();
        System.out.println("compact: position " + buffer.position() + " limit " + buffer.limit());
        buffer.clear();
        try {
            buffer.put(new byte[9]);
        } catch (BufferOverflowException expected) {
            System.out.println("overflow keeps position " + buffer.position());
        }
        try {
            buffer.position(9);
        } catch (IllegalArgumentException expected) {
            System.out.println("bad position rejected");
        }
        buffer.limit(4).rewind();
        System.out.println("limit/rewind: " + buffer.position() + "/" + buffer.limit() + " hasRemaining " + buffer.hasRemaining());
        byte[] backing = {9, 8, 7, 6};
        ByteBuffer wrapped = ByteBuffer.wrap(backing, 1, 2);
        System.out.println("wrapped: " + wrapped.position() + " " + wrapped.limit() + " " + wrapped.capacity() + " array " + (wrapped.array() == backing) + " offset " + wrapped.arrayOffset() + " hasArray " + wrapped.hasArray());
        ByteBuffer slice = wrapped.slice();
        System.out.println("slice: " + slice.capacity() + " " + slice.get(0) + " offset " + slice.arrayOffset());
        System.out.println("equal buffers: " + ByteBuffer.wrap(new byte[] {1, 2}).equals(ByteBuffer.wrap(new byte[] {0, 1, 2}, 1, 2)));
    }
}
