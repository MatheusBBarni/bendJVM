import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public final class HostCallbacks {
    static final class Named {
        private final String name;
        Named(String name) { this.name = name; }
        private String decorate(String text) { return "<" + text + ">"; }
        @Override public String toString() { return decorate(name); }
    }

    static final class Exploding {
        @Override public String toString() { throw new IllegalStateException("toString failed"); }
    }

    // Equal keys share a hash bucket with an unequal key, forcing chained equals callbacks.
    static final class Key {
        private final int id;
        Key(int id) { this.id = id; }
        @Override public boolean equals(Object other) {
            return other instanceof Key && ((Key) other).id == id;
        }
        @Override public int hashCode() { return id % 2; }
    }

    public static void main(String[] args) {
        Named named = new Named("alpha");
        System.out.println(named);
        System.out.println(String.valueOf(named));
        StringBuilder builder = new StringBuilder("value=").append(named).append('!');
        System.out.println(builder.toString());
        System.out.println(new StringBuilder().append((Object) null).append(builder.length()));
        try {
            System.out.println(new Exploding());
            System.out.println("unreachable");
        } catch (IllegalStateException expected) {
            System.out.println("caught " + expected.getMessage());
        }
        System.out.println(named);

        List<Key> keys = new ArrayList<Key>();
        keys.add(new Key(1));
        keys.add(new Key(3));
        keys.add(new Key(5));
        System.out.println(keys.contains(new Key(5)));
        System.out.println(keys.contains(new Key(7)));

        Map<Key, String> map = new HashMap<Key, String>();
        map.put(new Key(1), "one");
        map.put(new Key(3), "three");
        map.put(new Key(3), "three again");
        System.out.println(map.get(new Key(3)));
        System.out.println(map.get(new Key(1)));
        System.out.println(map.get(new Key(9)));
        System.out.println(map.size());
    }
}
