import java.lang.reflect.Constructor;
import java.lang.reflect.Method;

// InnerClasses/EnclosingMethod reflection: simple and canonical names, enclosing
// and declaring classes, member/local/anonymous classification, getDeclaredClasses
// and getClasses (JDK 8 java.lang.Class).
public class NestedClasses {
    public static class PublicMember { public interface Deep {} }
    class InnerMember {}
    private static class PrivateMember {}
    public static class Parent { public static class Inherited {} }
    public static class Child extends Parent { public static class Own {} }
    static Class<?> fromInitializer;
    static { class StaticLocal {} fromInitializer = StaticLocal.class; }
    Class<?> fromConstructor;
    NestedClasses() { class CtorLocal {} fromConstructor = CtorLocal.class; }

    static String name(Class<?> c) { return c == null ? "null" : c.getName(); }
    static String member(Object m) { return m == null ? "null" : m instanceof Method ? ((Method) m).getName() : "ctor " + ((Constructor<?>) m).getParameterCount(); }

    static void describe(Class<?> c) {
        System.out.println(c.getName() + " simple='" + c.getSimpleName() + "' canonical=" + c.getCanonicalName()
            + " enclosing=" + name(c.getEnclosingClass()) + " declaring=" + name(c.getDeclaringClass()));
        System.out.println("  member=" + c.isMemberClass() + " local=" + c.isLocalClass() + " anonymous=" + c.isAnonymousClass()
            + " method=" + member(c.getEnclosingMethod()) + " constructor=" + member(c.getEnclosingConstructor()));
    }

    Object anonymous() { return new Object() { public String toString() { return "anon"; } }; }

    public static void main(String[] args) {
        class MethodLocal {}
        describe(NestedClasses.class);
        describe(PublicMember.class);
        describe(PublicMember.Deep.class);
        describe(InnerMember.class);
        describe(PrivateMember.class);
        describe(MethodLocal.class);
        describe(new NestedClasses().anonymous().getClass());
        describe(fromInitializer);
        describe(new NestedClasses().fromConstructor);
        describe(PublicMember[].class);
        describe(MethodLocal[].class);
        describe(int[][].class);
        StringBuilder declared = new StringBuilder();
        for (Class<?> c : NestedClasses.class.getDeclaredClasses()) declared.append(c.getSimpleName()).append(' ');
        System.out.println("declared " + declared.toString().length());
        StringBuilder publics = new StringBuilder();
        for (Class<?> c : Child.class.getClasses()) publics.append(c.getSimpleName()).append(' ');
        System.out.println("classes " + publics);
        System.out.println("top " + String.class.getSimpleName() + " " + String.class.getCanonicalName() + " " + name(String.class.getEnclosingClass()));
    }
}
