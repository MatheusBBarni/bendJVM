package sun.nio.ch;

import java.nio.channels.CancelledKeyException;
import java.nio.channels.SelectableChannel;
import java.nio.channels.SelectionKey;
import java.nio.channels.Selector;

public final class SelectionKeyImpl extends SelectionKey {
    private final SelectableChannel channel;
    private final SelectorImpl selector;
    private volatile int interest;
    private volatile int ready;
    private volatile boolean valid = true;

    SelectionKeyImpl(SelectableChannel channel, SelectorImpl selector, int interest) {
        this.channel = channel;
        this.selector = selector;
        this.interest = interest;
    }

    public SelectableChannel channel() {
        return channel;
    }

    public Selector selector() {
        return selector;
    }

    public boolean isValid() {
        return valid;
    }

    public void cancel() {
        synchronized (this) {
            if (!valid) {
                return;
            }
            valid = false;
        }
        selector.cancelled(this);
    }

    void invalidate() {
        valid = false;
    }

    public int interestOps() {
        if (!valid) {
            throw new CancelledKeyException();
        }
        return interest;
    }

    public SelectionKey interestOps(int ops) {
        if (!valid) {
            throw new CancelledKeyException();
        }
        if ((ops & ~channel.validOps()) != 0) {
            throw new IllegalArgumentException();
        }
        interest = ops;
        return this;
    }

    public int readyOps() {
        if (!valid) {
            throw new CancelledKeyException();
        }
        return ready;
    }

    void setReady(int ops) {
        ready = ops;
    }

    int interest() {
        return interest;
    }

    public String toString() {
        return "channel=" + channel + ", selector=" + selector + (valid ? ", interestOps=" + interest + ", readyOps=" + ready : ", invalid");
    }
}
