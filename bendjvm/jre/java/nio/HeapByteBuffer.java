package java.nio;

class HeapByteBuffer extends ByteBuffer {
    HeapByteBuffer(byte[] buf, int position, int limit, int offset) {
        super(position, limit, buf.length - offset, buf, offset);
    }

    private HeapByteBuffer(byte[] buf, int position, int limit, int capacity, int offset) {
        super(position, limit, capacity, buf, offset);
    }

    public byte get() {
        return hb[offset + nextGetIndex(1)];
    }

    public byte get(int index) {
        return hb[offset + checkIndex(index)];
    }

    public ByteBuffer put(byte b) {
        hb[offset + nextPutIndex(1)] = b;
        return this;
    }

    public ByteBuffer put(int index, byte b) {
        hb[offset + checkIndex(index)] = b;
        return this;
    }

    public ByteBuffer slice() {
        int rem = remaining();
        return new HeapByteBuffer(hb, 0, rem, rem, position() + offset);
    }

    public ByteBuffer duplicate() {
        return new HeapByteBuffer(hb, position(), limit(), capacity(), offset);
    }

    public ByteBuffer compact() {
        int rem = remaining();
        System.arraycopy(hb, offset + position(), hb, offset, rem);
        position(rem);
        limit(capacity());
        return this;
    }
}
