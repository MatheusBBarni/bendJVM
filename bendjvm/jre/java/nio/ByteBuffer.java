package java.nio;

/** Heap byte buffers (JDK 8 API subset); direct buffers are not supported. */
public abstract class ByteBuffer extends Buffer implements Comparable<ByteBuffer> {
    final byte[] hb;
    final int offset;

    ByteBuffer(int position, int limit, int capacity, byte[] hb, int offset) {
        super(position, limit, capacity);
        this.hb = hb;
        this.offset = offset;
    }

    public static ByteBuffer allocate(int capacity) {
        if (capacity < 0) {
            throw new IllegalArgumentException("Negative capacity: " + capacity);
        }
        return new HeapByteBuffer(new byte[capacity], 0, capacity, 0);
    }

    public static ByteBuffer wrap(byte[] array, int offset, int length) {
        checkBounds(offset, length, array.length);
        return new HeapByteBuffer(array, offset, offset + length, 0);
    }

    public static ByteBuffer wrap(byte[] array) {
        return wrap(array, 0, array.length);
    }

    public abstract byte get();

    public abstract ByteBuffer put(byte b);

    public abstract byte get(int index);

    public abstract ByteBuffer put(int index, byte b);

    public abstract ByteBuffer slice();

    public abstract ByteBuffer duplicate();

    public abstract ByteBuffer compact();

    public ByteBuffer get(byte[] dst, int offset, int length) {
        checkBounds(offset, length, dst.length);
        if (length > remaining()) {
            throw new BufferUnderflowException();
        }
        int start = nextGetIndex(length);
        System.arraycopy(hb, this.offset + start, dst, offset, length);
        return this;
    }

    public ByteBuffer get(byte[] dst) {
        return get(dst, 0, dst.length);
    }

    public ByteBuffer put(ByteBuffer src) {
        if (src == this) {
            throw new IllegalArgumentException();
        }
        int n = src.remaining();
        if (n > remaining()) {
            throw new BufferOverflowException();
        }
        for (int i = 0; i < n; i++) {
            put(src.get());
        }
        return this;
    }

    public ByteBuffer put(byte[] src, int offset, int length) {
        checkBounds(offset, length, src.length);
        if (length > remaining()) {
            throw new BufferOverflowException();
        }
        int start = nextPutIndex(length);
        System.arraycopy(src, offset, hb, this.offset + start, length);
        return this;
    }

    public final ByteBuffer put(byte[] src) {
        return put(src, 0, src.length);
    }

    public final boolean hasArray() {
        return true;
    }

    public final byte[] array() {
        return hb;
    }

    public final int arrayOffset() {
        return offset;
    }

    public boolean isDirect() {
        return false;
    }

    public boolean isReadOnly() {
        return false;
    }

    public String toString() {
        return getClass().getName() + "[pos=" + position() + " lim=" + limit() + " cap=" + capacity() + "]";
    }

    public int hashCode() {
        int h = 1;
        int p = position();
        for (int i = limit() - 1; i >= p; i--) {
            h = 31 * h + (int) get(i);
        }
        return h;
    }

    public boolean equals(Object ob) {
        if (this == ob) {
            return true;
        }
        if (!(ob instanceof ByteBuffer)) {
            return false;
        }
        ByteBuffer that = (ByteBuffer) ob;
        if (this.remaining() != that.remaining()) {
            return false;
        }
        int p = this.position();
        for (int i = this.limit() - 1, j = that.limit() - 1; i >= p; i--, j--) {
            if (get(i) != that.get(j)) {
                return false;
            }
        }
        return true;
    }

    public int compareTo(ByteBuffer that) {
        int n = this.position() + Math.min(this.remaining(), that.remaining());
        for (int i = this.position(), j = that.position(); i < n; i++, j++) {
            int cmp = this.get(i) - that.get(j);
            if (cmp != 0) {
                return cmp;
            }
        }
        return this.remaining() - that.remaining();
    }
}
