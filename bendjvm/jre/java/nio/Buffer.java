package java.nio;

/** JDK 8 java.nio.Buffer: position <= limit <= capacity, kept entirely in Java. */
public abstract class Buffer {
    private int position;
    private int limit;
    private final int capacity;

    Buffer(int position, int limit, int capacity) {
        if (capacity < 0) {
            throw new IllegalArgumentException("Negative capacity: " + capacity);
        }
        this.capacity = capacity;
        limit(limit);
        position(position);
    }

    public final int capacity() {
        return capacity;
    }

    public final int position() {
        return position;
    }

    public final Buffer position(int newPosition) {
        if (newPosition > limit || newPosition < 0) {
            throw new IllegalArgumentException();
        }
        position = newPosition;
        return this;
    }

    public final int limit() {
        return limit;
    }

    public final Buffer limit(int newLimit) {
        if (newLimit > capacity || newLimit < 0) {
            throw new IllegalArgumentException();
        }
        limit = newLimit;
        if (position > newLimit) {
            position = newLimit;
        }
        return this;
    }

    public final Buffer clear() {
        position = 0;
        limit = capacity;
        return this;
    }

    public final Buffer flip() {
        limit = position;
        position = 0;
        return this;
    }

    public final Buffer rewind() {
        position = 0;
        return this;
    }

    public final int remaining() {
        return limit - position;
    }

    public final boolean hasRemaining() {
        return position < limit;
    }

    public abstract boolean isReadOnly();

    public abstract boolean hasArray();

    public abstract Object array();

    public abstract int arrayOffset();

    public abstract boolean isDirect();

    // Advances the position by n and returns the old one (BufferUnderflowException when short).
    final int nextGetIndex(int n) {
        if (limit - position < n) {
            throw new BufferUnderflowException();
        }
        int p = position;
        position = p + n;
        return p;
    }

    final int nextPutIndex(int n) {
        if (limit - position < n) {
            throw new BufferOverflowException();
        }
        int p = position;
        position = p + n;
        return p;
    }

    final int checkIndex(int i) {
        if (i < 0 || i >= limit) {
            throw new IndexOutOfBoundsException();
        }
        return i;
    }

    static void checkBounds(int off, int len, int size) {
        if ((off | len | (off + len) | (size - (off + len))) < 0) {
            throw new IndexOutOfBoundsException();
        }
    }
}
