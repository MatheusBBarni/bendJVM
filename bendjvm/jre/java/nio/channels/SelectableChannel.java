package java.nio.channels;

import java.io.IOException;

/**
 * A channel usable with a Selector. BendJVM folds the JDK's
 * AbstractInterruptibleChannel/AbstractSelectableChannel layers into this class.
 */
public abstract class SelectableChannel implements Channel {
    private final Object regLock = new Object();
    private final Object closeLock = new Object();
    private volatile boolean open = true;
    private volatile boolean blocking = true;
    private sun.nio.ch.SelectionKeyImpl[] keys = new sun.nio.ch.SelectionKeyImpl[0];

    protected SelectableChannel() {
    }

    public abstract int validOps();

    public final boolean isOpen() {
        return open;
    }

    public final boolean isBlocking() {
        return blocking;
    }

    public final Object blockingLock() {
        return regLock;
    }

    public final SelectableChannel configureBlocking(boolean block) throws IOException {
        synchronized (regLock) {
            if (!open) {
                throw new ClosedChannelException();
            }
            if (block && isRegistered()) {
                throw new IllegalBlockingModeException();
            }
            blocking = block;
        }
        return this;
    }

    public final boolean isRegistered() {
        synchronized (regLock) {
            for (sun.nio.ch.SelectionKeyImpl key : keys) {
                if (key.isValid()) {
                    return true;
                }
            }
            return false;
        }
    }

    public final SelectionKey keyFor(Selector sel) {
        synchronized (regLock) {
            for (sun.nio.ch.SelectionKeyImpl key : keys) {
                if (key.selector() == sel && key.isValid()) {
                    return key;
                }
            }
            return null;
        }
    }

    public final SelectionKey register(Selector sel, int ops) throws ClosedChannelException {
        return register(sel, ops, null);
    }

    public final SelectionKey register(Selector sel, int ops, Object att) throws ClosedChannelException {
        synchronized (regLock) {
            if (!open) {
                throw new ClosedChannelException();
            }
            if ((ops & ~validOps()) != 0) {
                throw new IllegalArgumentException();
            }
            if (blocking) {
                throw new IllegalBlockingModeException();
            }
            if (!(sel instanceof sun.nio.ch.SelectorImpl)) {
                throw new IllegalSelectorException();
            }
            SelectionKey existing = keyFor(sel);
            if (existing != null) {
                existing.interestOps(ops);
                existing.attach(att);
                return existing;
            }
            sun.nio.ch.SelectionKeyImpl key = ((sun.nio.ch.SelectorImpl) sel).register(this, ops, att);
            sun.nio.ch.SelectionKeyImpl[] grown = new sun.nio.ch.SelectionKeyImpl[keys.length + 1];
            System.arraycopy(keys, 0, grown, 0, keys.length);
            grown[keys.length] = key;
            keys = grown;
            return key;
        }
    }

    public final void close() throws IOException {
        synchronized (closeLock) {
            if (!open) {
                return;
            }
            open = false;
            sun.nio.ch.SelectionKeyImpl[] registered;
            synchronized (regLock) {
                registered = keys;
            }
            for (sun.nio.ch.SelectionKeyImpl key : registered) {
                key.cancel();
            }
            implCloseChannel();
        }
    }

    protected abstract void implCloseChannel() throws IOException;

    // The host handle the selector polls (0 while the channel has none).
    public abstract int hostHandle();

    // Converts a host failure seen by a blocking operation: a close by another
    // thread is AsynchronousCloseException, a close of our own is ClosedChannelException.
    protected final void ensureOpen() throws ClosedChannelException {
        if (!open) {
            throw new ClosedChannelException();
        }
    }

    protected final int flags() {
        return blocking ? sun.nio.ch.HostIO.INTERRUPTIBLE : sun.nio.ch.HostIO.NONBLOCKING;
    }

    // An interrupted blocking operation closes the channel (JDK begin/end).
    protected final IOException interrupted(ClosedByInterruptException error) {
        try {
            close();
        } catch (IOException ignored) {
            // the interrupt is what the caller reports
        }
        return error;
    }
}
