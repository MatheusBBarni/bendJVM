import java.io.IOException;
import java.net.InetSocketAddress;
import java.nio.BufferOverflowException;
import java.nio.BufferUnderflowException;
import java.nio.ByteBuffer;
import java.nio.channels.AsynchronousCloseException;
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
import java.util.Set;

// One call of every method in plan 05's "Required Java/API compatibility slice"
// table that the other fixtures do not already print (TLS is in TlsFixture).
public class ApiSurface {
    static volatile boolean flag;
    static volatile long wideVolatile;
    static volatile double doubleVolatile;

    public static void main(String[] args) throws Exception {
        threads();
        monitors();
        time();
        buffers();
        selectors();
        exceptions();
    }

    static void threads() throws Exception {
        Runnable task = new Runnable() {
            public void run() {
                flag = true;
            }
        };
        Thread named = new Thread(task, "named");
        named.setName("renamed");
        System.out.println("name: " + named.getName() + " id positive: " + (named.getId() > 0) + " state: " + named.getState());
        named.setDaemon(false);
        named.start();
        named.join(0, 500);
        named.join(1000L);
        named.join();
        System.out.println("ran: " + flag + " alive: " + named.isAlive() + " state: " + named.getState());
        Thread.sleep(1, 999999);
        Thread.yield();
        System.out.println("holdsLock outside: " + Thread.holdsLock(ApiSurface.class));
        Thread.UncaughtExceptionHandler handler = new Thread.UncaughtExceptionHandler() {
            public void uncaughtException(Thread t, Throwable e) {
            }
        };
        // On a thread that has not started: JDK 8 and newer JDKs differ for terminated threads.
        Thread fresh = new Thread(task);
        fresh.setUncaughtExceptionHandler(handler);
        System.out.println("handler kept: " + (fresh.getUncaughtExceptionHandler() == handler));
        Thread.UncaughtExceptionHandler previous = Thread.getDefaultUncaughtExceptionHandler();
        Thread.setDefaultUncaughtExceptionHandler(handler);
        System.out.println("default set: " + (Thread.getDefaultUncaughtExceptionHandler() == handler));
        Thread.setDefaultUncaughtExceptionHandler(previous);
        System.out.println("states: " + Thread.State.values().length + " " + Thread.State.valueOf("BLOCKED"));
    }

    static synchronized void staticLocked() {
        System.out.println("static synchronized holds class: " + Thread.holdsLock(ApiSurface.class));
    }

    static void monitors() throws Exception {
        final Object lock = new Object();
        synchronized (lock) {
            lock.wait(1);
            lock.wait(1, 5);
            lock.notify();
            lock.notifyAll();
        }
        staticLocked();
        final boolean[] woken = new boolean[1];
        Thread waiter = new Thread(new Runnable() {
            public void run() {
                synchronized (lock) {
                    while (!woken[0]) {
                        try {
                            lock.wait();
                        } catch (InterruptedException e) {
                            return;
                        }
                    }
                }
            }
        });
        waiter.start();
        while (waiter.getState() != Thread.State.WAITING) {
            Thread.yield();
        }
        synchronized (lock) {
            woken[0] = true;
            lock.notifyAll();
        }
        waiter.join();
        System.out.println("untimed wait woken: " + !waiter.isAlive());
    }

    static void time() {
        long a = System.nanoTime();
        long b = System.nanoTime();
        long now = System.currentTimeMillis();
        wideVolatile = Long.MAX_VALUE;
        doubleVolatile = Math.PI;
        System.out.println("clocks: " + (b >= a) + " " + (now > 1500000000000L) + " volatile wide: " + (wideVolatile == Long.MAX_VALUE) + " " + (doubleVolatile == Math.PI));
    }

    static void buffers() {
        ByteBuffer buffer = ByteBuffer.allocate(6);
        buffer.put(0, (byte) 9);
        buffer.position(1);
        buffer.put((byte) 7);
        System.out.println("indexed: " + buffer.get(0) + " position " + buffer.position() + " limit " + buffer.limit() + " capacity " + buffer.capacity());
        buffer.flip();
        System.out.println("flip remaining " + buffer.remaining() + " hasRemaining " + buffer.hasRemaining() + " get " + buffer.get());
        buffer.rewind();
        buffer.clear();
        byte[] chunk = {1, 2, 3};
        buffer.put(chunk, 0, 2).put(chunk);
        buffer.flip();
        byte[] out = new byte[5];
        buffer.get(out, 0, 5);
        System.out.println("bulk: " + out[0] + out[1] + out[2] + out[3] + out[4] + " hasArray " + buffer.hasArray() + " offset " + buffer.arrayOffset() + " array " + buffer.array().length);
        ByteBuffer wrapped = ByteBuffer.wrap(chunk);
        System.out.println("wrap: " + wrapped.remaining() + " " + wrapped.get(2));
    }

    static void selectors() throws Exception {
        Selector selector = Selector.open();
        ServerSocketChannel server = ServerSocketChannel.open();
        server.bind(new InetSocketAddress("127.0.0.1", 0));
        server.configureBlocking(false);
        SelectionKey accept = server.register(selector, SelectionKey.OP_ACCEPT);
        int port = ((InetSocketAddress) server.getLocalAddress()).getPort();
        System.out.println("selectNow empty: " + selector.selectNow() + " keys " + selector.keys().size() + " open " + selector.isOpen() + " " + server.isOpen());

        SocketChannel client = SocketChannel.open();
        client.configureBlocking(false);
        boolean immediate = client.connect(new InetSocketAddress("127.0.0.1", port));
        SelectionKey connect = client.register(selector, SelectionKey.OP_CONNECT);
        while (!client.finishConnect()) {
            selector.select(50);
        }
        System.out.println("connected: " + client.isConnected() + " pending " + client.isConnectionPending() + " immediate-or-finished " + (immediate || client.isConnected()));
        selector.select(1000);
        Set<SelectionKey> selected = selector.selectedKeys();
        boolean sawAccept = false;
        for (Iterator<SelectionKey> it = selected.iterator(); it.hasNext(); ) {
            SelectionKey key = it.next();
            it.remove();
            if (key.isValid() && key.isAcceptable()) {
                sawAccept = key.channel() == server && key.selector() == selector && (key.readyOps() & SelectionKey.OP_ACCEPT) != 0;
            }
        }
        System.out.println("acceptable key: " + sawAccept + " selected now " + selected.size());
        SocketChannel accepted = server.accept();
        connect.interestOps(SelectionKey.OP_WRITE);
        selector.select(1000);
        boolean writable = false;
        boolean connectable = false;
        for (SelectionKey key : selector.selectedKeys()) {
            writable |= key == connect && key.isWritable();
            connectable |= key == connect && key.isConnectable();
        }
        selector.selectedKeys().clear();
        System.out.println("writable key: " + writable + " connectable " + connectable + " interest " + connect.interestOps());
        client.write(ByteBuffer.wrap(new byte[] {42}));
        accepted.configureBlocking(true);
        ByteBuffer one = ByteBuffer.allocate(1);
        accepted.read(one);
        System.out.println("read through channel: " + one.get(0));
        accept.cancel();
        selector.selectNow();
        System.out.println("cancelled key removed: " + !selector.keys().contains(accept) + " valid " + accept.isValid());
        selector.wakeup();
        client.close();
        accepted.close();
        server.close();
        selector.close();
        System.out.println("closed: " + client.isOpen() + " " + server.isOpen() + " " + selector.isOpen());
    }

    static void exceptions() {
        Class<?>[] types = {InterruptedException.class, IllegalThreadStateException.class, IllegalMonitorStateException.class,
            SecurityException.class, UnsatisfiedLinkError.class, BufferOverflowException.class, BufferUnderflowException.class,
            IllegalBlockingModeException.class, ClosedChannelException.class, AsynchronousCloseException.class,
            ClosedByInterruptException.class, CancelledKeyException.class, ClosedSelectorException.class,
            javax.net.ssl.SSLException.class, javax.net.ssl.SSLHandshakeException.class};
        StringBuilder names = new StringBuilder();
        for (Class<?> type : types) {
            names.append(type.getSimpleName()).append(' ');
        }
        System.out.println("exceptions: " + names.toString().trim());
        System.out.println("io hierarchy: " + (new AsynchronousCloseException() instanceof IOException) + " " + (new ClosedByInterruptException() instanceof AsynchronousCloseException));
    }
}
