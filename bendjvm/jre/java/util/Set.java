package java.util;

/** The Set operations the MiniJRE supports (JDK 8 signatures). */
public interface Set<E> extends Collection<E> {
    int size();

    boolean isEmpty();

    boolean contains(Object o);

    Iterator<E> iterator();

    boolean add(E e);

    boolean remove(Object o);

    void clear();

    Object[] toArray();

    <T> T[] toArray(T[] a);

    boolean containsAll(Collection<?> c);

    boolean addAll(Collection<? extends E> c);

    boolean removeAll(Collection<?> c);

    boolean retainAll(Collection<?> c);
}
