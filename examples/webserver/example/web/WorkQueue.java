package example.web;

import java.net.Socket;

/** A bounded FIFO of accepted connections guarded by its monitor (wait/notifyAll). */
final class WorkQueue {
    private final Socket[] items;
    private int head;
    private int count;
    private boolean closed;

    WorkQueue(int capacity) {
        items = new Socket[capacity];
    }

    synchronized void put(Socket socket) throws InterruptedException {
        while (count == items.length && !closed) {
            wait();
        }
        if (closed) {
            throw new IllegalStateException("queue closed");
        }
        items[(head + count) % items.length] = socket;
        count++;
        notifyAll();
    }

    /** The next connection, or null once the queue is closed and drained. */
    synchronized Socket take() throws InterruptedException {
        while (count == 0 && !closed) {
            wait();
        }
        if (count == 0) {
            return null;
        }
        Socket socket = items[head];
        items[head] = null;
        head = (head + 1) % items.length;
        count--;
        notifyAll();
        return socket;
    }

    synchronized void close() {
        closed = true;
        notifyAll();
    }
}
