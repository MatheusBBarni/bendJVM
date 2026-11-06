package java.net;

import java.io.IOException;
import java.io.OutputStream;

class SocketOutputStream extends OutputStream {
    private final Socket socket;

    SocketOutputStream(Socket socket) {
        this.socket = socket;
    }

    public void write(int b) throws IOException {
        write(new byte[] {(byte) b}, 0, 1);
    }

    public void write(byte[] b) throws IOException {
        write(b, 0, b.length);
    }

    public void write(byte[] b, int off, int len) throws IOException {
        if (off < 0 || len < 0 || len > b.length - off) {
            throw new IndexOutOfBoundsException();
        }
        socket.writeFrom(b, off, len);
    }

    public void flush() throws IOException {
    }

    public void close() throws IOException {
        socket.close();
    }
}
