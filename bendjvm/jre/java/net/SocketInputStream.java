package java.net;

import java.io.IOException;
import java.io.InputStream;

/** Socket.getInputStream(): blocking reads that park only the reading thread. */
class SocketInputStream extends InputStream {
    private final Socket socket;
    private boolean eof;

    SocketInputStream(Socket socket) {
        this.socket = socket;
    }

    public int read() throws IOException {
        byte[] one = new byte[1];
        int n = read(one, 0, 1);
        return n <= 0 ? -1 : one[0] & 0xFF;
    }

    public int read(byte[] b) throws IOException {
        return read(b, 0, b.length);
    }

    public int read(byte[] b, int off, int len) throws IOException {
        if (off < 0 || len < 0 || len > b.length - off) {
            throw new IndexOutOfBoundsException();
        }
        if (len == 0) {
            return 0;
        }
        if (eof || socket.isInputShutdown()) {
            return -1;
        }
        int n = socket.readInto(b, off, len);
        if (n < 0) {
            eof = true;
            return -1;
        }
        return n;
    }

    public int available() throws IOException {
        return 0;
    }

    public void close() throws IOException {
        socket.close();
    }
}
