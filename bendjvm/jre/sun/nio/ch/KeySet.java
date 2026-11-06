package sun.nio.ch;

import java.nio.channels.SelectionKey;
import java.util.Collection;
import java.util.ConcurrentModificationException;
import java.util.Iterator;
import java.util.NoSuchElementException;
import java.util.Set;

/** An identity set of selection keys; `addable` is false for selectedKeys(). */
final class KeySet implements Set<SelectionKey> {
    private SelectionKey[] items = new SelectionKey[4];
    private int size;
    private int modCount;
    private final boolean mutable;

    KeySet(boolean mutable) {
        this.mutable = mutable;
    }

    // Internal mutation by the selector, bypassing the view restrictions.
    void put(SelectionKey key) {
        if (indexOf(key) >= 0) {
            return;
        }
        if (size == items.length) {
            SelectionKey[] grown = new SelectionKey[size * 2];
            System.arraycopy(items, 0, grown, 0, size);
            items = grown;
        }
        items[size++] = key;
        modCount++;
    }

    boolean drop(Object key) {
        int i = indexOf(key);
        if (i < 0) {
            return false;
        }
        System.arraycopy(items, i + 1, items, i, size - i - 1);
        items[--size] = null;
        modCount++;
        return true;
    }

    SelectionKey at(int i) {
        return items[i];
    }

    private int indexOf(Object key) {
        for (int i = 0; i < size; i++) {
            if (items[i] == key) {
                return i;
            }
        }
        return -1;
    }

    private void checkMutable() {
        if (!mutable) {
            throw new UnsupportedOperationException();
        }
    }

    public int size() {
        return size;
    }

    public boolean isEmpty() {
        return size == 0;
    }

    public boolean contains(Object o) {
        return indexOf(o) >= 0;
    }

    public Iterator<SelectionKey> iterator() {
        return new Iterator<SelectionKey>() {
            private int next;
            private int last = -1;
            private int expected = modCount;

            public boolean hasNext() {
                return next < size;
            }

            public SelectionKey next() {
                if (expected != modCount) {
                    throw new ConcurrentModificationException();
                }
                if (next >= size) {
                    throw new NoSuchElementException();
                }
                last = next;
                return items[next++];
            }

            public void remove() {
                checkMutable();
                if (last < 0) {
                    throw new IllegalStateException();
                }
                if (expected != modCount) {
                    throw new ConcurrentModificationException();
                }
                drop(items[last]);
                next = last;
                last = -1;
                expected = modCount;
            }
        };
    }

    public boolean add(SelectionKey e) {
        throw new UnsupportedOperationException();
    }

    public boolean remove(Object o) {
        checkMutable();
        return drop(o);
    }

    public void clear() {
        checkMutable();
        for (int i = 0; i < size; i++) {
            items[i] = null;
        }
        size = 0;
        modCount++;
    }

    public Object[] toArray() {
        Object[] out = new Object[size];
        System.arraycopy(items, 0, out, 0, size);
        return out;
    }

    @SuppressWarnings("unchecked")
    public <T> T[] toArray(T[] a) {
        if (a.length < size) {
            a = (T[]) new SelectionKey[size];
        }
        System.arraycopy(items, 0, a, 0, size);
        if (a.length > size) {
            a[size] = null;
        }
        return a;
    }

    public boolean containsAll(Collection<?> c) {
        for (Object o : c) {
            if (!contains(o)) {
                return false;
            }
        }
        return true;
    }

    public boolean addAll(Collection<? extends SelectionKey> c) {
        throw new UnsupportedOperationException();
    }

    public boolean removeAll(Collection<?> c) {
        checkMutable();
        boolean changed = false;
        for (Object o : c) {
            changed |= drop(o);
        }
        return changed;
    }

    public boolean retainAll(Collection<?> c) {
        checkMutable();
        boolean changed = false;
        for (int i = size - 1; i >= 0; i--) {
            if (!c.contains(items[i])) {
                drop(items[i]);
                changed = true;
            }
        }
        return changed;
    }

    public String toString() {
        StringBuilder text = new StringBuilder("[");
        for (int i = 0; i < size; i++) {
            if (i > 0) {
                text.append(", ");
            }
            text.append(items[i]);
        }
        return text.append(']').toString();
    }
}
