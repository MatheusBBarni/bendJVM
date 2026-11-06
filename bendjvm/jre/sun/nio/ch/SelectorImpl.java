package sun.nio.ch;

import java.io.IOException;
import java.nio.channels.ClosedSelectorException;
import java.nio.channels.SelectableChannel;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;
import java.util.Set;

/**
 * Readiness selection over host socket handles. A blocking select parks only
 * its thread; wakeup() from another thread (or an interrupt) ends it. Ready
 * keys are added to selectedKeys once, and readiness of keys already selected
 * is merged into their ready set (JDK semantics).
 */
public final class SelectorImpl extends Selector {
    private static int nextId;

    private final int id;
    private final KeySet keys = new KeySet(false);
    private final KeySet selected = new KeySet(true);
    private final KeySet cancelled = new KeySet(true);
    private volatile boolean open = true;

    public SelectorImpl() {
        synchronized (SelectorImpl.class) {
            id = ++nextId;
        }
    }

    public boolean isOpen() {
        return open;
    }

    private void ensureOpen() {
        if (!open) {
            throw new ClosedSelectorException();
        }
    }

    public SelectionKeyImpl register(SelectableChannel channel, int ops, Object att) {
        synchronized (this) {
            ensureOpen();
            SelectionKeyImpl key = new SelectionKeyImpl(channel, this, ops);
            key.attach(att);
            keys.put(key);
            return key;
        }
    }

    void cancelled(SelectionKeyImpl key) {
        synchronized (this) {
            cancelled.put(key);
        }
    }

    public Set<SelectionKey> keys() {
        ensureOpen();
        return keys;
    }

    public Set<SelectionKey> selectedKeys() {
        ensureOpen();
        return selected;
    }

    // Deregisters cancelled keys (selection steps 1 and 3).
    private void processCancelled() {
        synchronized (this) {
            while (cancelled.size() > 0) {
                SelectionKey key = cancelled.at(0);
                cancelled.drop(key);
                keys.drop(key);
                selected.drop(key);
            }
        }
    }

    private int doSelect(int arg) throws IOException {
        ensureOpen();
        processCancelled();
        SelectionKeyImpl[] polled;
        int count;
        synchronized (this) {
            polled = new SelectionKeyImpl[keys.size()];
            count = 0;
            for (int i = 0; i < keys.size(); i++) {
                SelectionKeyImpl key = (SelectionKeyImpl) keys.at(i);
                if (key.isValid() && key.interest() != 0 && key.channel().isOpen() && key.channel().hostHandle() != 0) {
                    polled[count++] = key;
                }
            }
        }
        byte[] request = new byte[Math.max(1, count * 5)];
        for (int i = 0; i < count; i++) {
            int h = polled[i].channel().hostHandle();
            request[i * 5] = (byte) (h >>> 24);
            request[i * 5 + 1] = (byte) (h >>> 16);
            request[i * 5 + 2] = (byte) (h >>> 8);
            request[i * 5 + 3] = (byte) h;
            request[i * 5 + 4] = (byte) polled[i].interest();
        }
        int ready = HostIO.call(HostIO.SELECT, id, arg | HostIO.INTERRUPTIBLE, request, 0, count * 5);
        processCancelled();
        int updated = 0;
        synchronized (this) {
            for (int r = 0; r < ready; r++) {
                int h = ((request[r * 5] & 0xFF) << 24) | ((request[r * 5 + 1] & 0xFF) << 16) | ((request[r * 5 + 2] & 0xFF) << 8) | (request[r * 5 + 3] & 0xFF);
                int ops = request[r * 5 + 4] & 0xFF;
                for (int i = 0; i < count; i++) {
                    SelectionKeyImpl key = polled[i];
                    if (!key.isValid() || key.channel().hostHandle() != h) {
                        continue;
                    }
                    int readyOps = ops & key.interest();
                    if (readyOps == 0) {
                        continue;
                    }
                    if (selected.contains(key)) {
                        if ((key.readyOps() | readyOps) != key.readyOps()) {
                            key.setReady(key.readyOps() | readyOps);
                            updated++;
                        }
                    } else {
                        key.setReady(readyOps);
                        selected.put(key);
                        updated++;
                    }
                }
            }
        }
        return updated;
    }

    public int selectNow() throws IOException {
        return doSelect(HostIO.NONBLOCKING);
    }

    public int select(long timeout) throws IOException {
        if (timeout < 0) {
            throw new IllegalArgumentException("Negative timeout");
        }
        return doSelect(timeout == 0 ? HostIO.FOREVER : timeout >= HostIO.FOREVER ? HostIO.FOREVER - 1 : (int) timeout);
    }

    public int select() throws IOException {
        return select(0);
    }

    public Selector wakeup() {
        if (open) {
            try {
                HostIO.call(HostIO.WAKEUP, id, 0);
            } catch (IOException ignored) {
                // a closed selector has nothing to wake
            }
        }
        return this;
    }

    public void close() throws IOException {
        synchronized (this) {
            if (!open) {
                return;
            }
            open = false;
        }
        wakeupClosed();
        synchronized (this) {
            for (int i = 0; i < keys.size(); i++) {
                ((SelectionKeyImpl) keys.at(i)).invalidate();
            }
        }
    }

    private void wakeupClosed() {
        try {
            HostIO.call(HostIO.WAKEUP, id, 1);
        } catch (IOException ignored) {
            // nothing was waiting
        }
    }

    public String toString() {
        return "sun.nio.ch.SelectorImpl@" + id;
    }
}
