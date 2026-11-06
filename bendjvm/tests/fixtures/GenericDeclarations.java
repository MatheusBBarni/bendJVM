import java.lang.reflect.Constructor;
import java.lang.reflect.GenericArrayType;
import java.lang.reflect.Method;
import java.lang.reflect.ParameterizedType;
import java.lang.reflect.Type;
import java.lang.reflect.TypeVariable;
import java.lang.reflect.WildcardType;
import java.util.List;
import java.util.Map;

// Class/method/constructor type parameters, generic interfaces, and TypeVariable
// identity (JDK 8 java.lang.reflect generics).
public class GenericDeclarations {
    interface Source<T> { T get(); }
    interface Keyed<K extends Comparable<K>, V> {}
    static class Base<A> {}
    static class Node<T extends Comparable<T>, U extends List<? super T>> extends Base<T[]> implements Source<T>, Keyed<T, Map<String, U>> {
        public T get() { return null; }
        public <R extends Number & Comparable<R>> R convert(Map<? extends T, ? super R> input, R[] seeds) { return null; }
        public <X> Node(X seed, List<? extends X> more) {}
    }

    static String show(Type type) {
        if (type instanceof Class) return "class " + ((Class<?>) type).getTypeName();
        if (type instanceof ParameterizedType) {
            ParameterizedType p = (ParameterizedType) type;
            StringBuilder out = new StringBuilder("param " + show(p.getRawType()) + " owner=" + (p.getOwnerType() == null ? "none" : show(p.getOwnerType())) + " args[");
            for (Type arg : p.getActualTypeArguments()) out.append(show(arg)).append(";");
            return out.append("]").toString();
        }
        if (type instanceof TypeVariable) {
            TypeVariable<?> v = (TypeVariable<?>) type;
            Object declaration = v.getGenericDeclaration();
            String where = declaration instanceof Class ? ((Class<?>) declaration).getSimpleName() : declaration instanceof Method ? ((Method) declaration).getName() : "ctor";
            return "var " + v.getName() + "@" + where;
        }
        if (type instanceof WildcardType) {
            WildcardType w = (WildcardType) type;
            return "wild up=" + w.getUpperBounds().length + " low=" + w.getLowerBounds().length + " " + w.getTypeName();
        }
        if (type instanceof GenericArrayType) return "array " + show(((GenericArrayType) type).getGenericComponentType());
        return "?";
    }

    static void variables(String label, TypeVariable<?>[] variables) {
        System.out.println(label + " count=" + variables.length);
        for (TypeVariable<?> v : variables) {
            System.out.print("  " + v.getName() + " " + v + " bounds:");
            for (Type bound : v.getBounds()) System.out.print(" " + show(bound) + " {" + bound.getTypeName() + "}");
            System.out.println();
        }
    }

    public static void main(String[] args) throws Exception {
        Class<?> node = Node.class;
        variables("Node", node.getTypeParameters());
        variables("Source", Source.class.getTypeParameters());
        variables("plain", String.class.getTypeParameters());
        System.out.println("super " + show(node.getGenericSuperclass()) + " {" + node.getGenericSuperclass().getTypeName() + "}");
        for (Type face : node.getGenericInterfaces()) System.out.println("iface " + show(face) + " {" + face.getTypeName() + "}");
        Method convert = null;
        for (Method m : node.getDeclaredMethods()) if (m.getName().equals("convert")) convert = m;
        variables("convert", convert.getTypeParameters());
        for (Type p : convert.getGenericParameterTypes()) System.out.println("convert param " + show(p) + " {" + p.getTypeName() + "}");
        System.out.println("convert return " + show(convert.getGenericReturnType()));
        System.out.println(convert.toGenericString());
        Constructor<?> constructor = node.getDeclaredConstructors()[0];
        variables("ctor", constructor.getTypeParameters());
        for (Type p : constructor.getGenericParameterTypes()) System.out.println("ctor param " + show(p));
        System.out.println(constructor.toGenericString());
        TypeVariable<?> t1 = node.getTypeParameters()[0];
        TypeVariable<?> t2 = (TypeVariable<?>) node.getMethod("get").getGenericReturnType();
        System.out.println("same var " + t1.equals(t2) + " " + (t1.hashCode() == t2.hashCode()) + " " + t1.equals(convert.getTypeParameters()[0]));
        System.out.println("impl " + t1.getClass().getName() + " " + node.getGenericSuperclass().getClass().getName());
    }
}
