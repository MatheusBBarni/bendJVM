import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

// JVMS 5.5 initialization triggers and ordering, plus JVMS 5.4.3.2 field resolution.
public class InitSemantics {
    static StringBuilder log = new StringBuilder();
    static void note(String s) { log.append(' ').append(s); }
    static void flush(String label) { System.out.println(label + ":" + log.toString()); log = new StringBuilder(); }

    static class Base { static { note("Base"); } static int inherited = 10; static int touch() { return 1; } }
    static class Child extends Base { static { note("Child"); } static int own = 20; }
    static class GrandChild extends Child { static { note("GrandChild"); } int value = 3; }

    static class NewTarget extends Base { static { note("NewTarget"); } }
    static class StaticCall { static { note("StaticCall"); } static int call() { return 4; } }
    static class Putter { static { note("Putter"); } static int slot; }
    static class Constant { static { note("Constant"); } static final int VALUE = 99; static final String TEXT = "text"; }
    static class ArrayOnly { static { note("ArrayOnly"); } }

    interface Plain { int X = Integer.parseInt("5"); }
    interface WithDefault { int Y = InitSemantics.mark("WithDefault", 6); default int d() { return 1; } }
    static int mark(String s, int v) { note(s); return v; }
    static class Implementor implements Plain, WithDefault { static { note("Implementor"); } }
    static class FieldViaClass implements Plain { static { note("FieldViaClass"); } }

    static class Boom { static int value = explode(); static int explode() { throw new IllegalStateException("boom"); } }
    static class ErrorBoom { static { if (true) throw new AssertionError("err"); } }

    static class CycleA { static int a = CycleB.b + 1; static { note("CycleA=" + a); } }
    static class CycleB { static int b = CycleA.a + 10; static { note("CycleB=" + b); } }

    static class Reflected { static { note("Reflected"); } static int field = 7; public static int method() { return 8; } public Reflected() {} }
    static class ForNamed { static { note("ForNamed"); } }
    static class ForNamedBase { static { note("ForNamedBase"); } }
    static class ForNamedSub extends ForNamedBase { static { note("ForNamedSub"); } }
    static class ReflectForNamed { static { note("ReflectForNamed"); } }
    static class ForNamedBoom { static { if (true) throw new IllegalArgumentException("forName boom"); } }
    static class StaticHolderBase { static { note("StaticHolderBase"); } public static int shared = 41; }
    static class StaticHolder extends StaticHolderBase { static { note("StaticHolder"); } }
    static class ForNamedLazy { static { note("ForNamedLazy"); } }

    public static void main(String[] args) throws Exception {
        System.out.println(Child.inherited);
        flush("getstatic inherited");
        System.out.println(Child.own);
        flush("getstatic own");
        System.out.println(new GrandChild().value);
        flush("new subclass");
        new NewTarget();
        flush("new");
        System.out.println(StaticCall.call());
        flush("invokestatic");
        Putter.slot = 5;
        flush("putstatic");
        System.out.println(Putter.slot);
        System.out.println(Constant.VALUE + Constant.TEXT);
        flush("constant");
        System.out.println(new ArrayOnly[2].length);
        flush("array");
        new Implementor();
        flush("class with default superinterface");
        System.out.println(FieldViaClass.X);
        flush("interface field via class");

        try { System.out.println(Boom.value); } catch (ExceptionInInitializerError e) {
            System.out.println("EIIE " + e.getCause().getClass().getName() + " " + e.getCause().getMessage());
        }
        try { System.out.println(Boom.value); } catch (NoClassDefFoundError e) { System.out.println("NCDFE"); }
        try { new ErrorBoom(); } catch (AssertionError e) { System.out.println("AssertionError " + e.getMessage()); }
        try { new ErrorBoom(); } catch (NoClassDefFoundError e) { System.out.println("NCDFE again"); }

        System.out.println(CycleA.a + " " + CycleB.b);
        flush("cycle");

        Class<?> reflected = Reflected.class;
        flush("class literal");
        Field f = reflected.getDeclaredField("field");
        flush("getDeclaredField");
        System.out.println(f.get(null));
        flush("Field.get");
        Method m = reflected.getMethod("method");
        System.out.println(m.invoke(null));
        Constructor<?> c = reflected.getConstructor();
        System.out.println(c.newInstance() != null);
        flush("reflection");

        Class.forName("InitSemantics$ForNamedLazy", false, InitSemantics.class.getClassLoader());
        flush("forName no init");
        Class.forName("InitSemantics$ForNamed");
        flush("forName");
        System.out.println(Class.forName("InitSemantics$ForNamedSub").getName());
        flush("forName subclass");
        Method forName = Class.class.getMethod("forName", String.class);
        System.out.println(((Class<?>) forName.invoke(null, "InitSemantics$ReflectForNamed")).getName());
        flush("reflective forName");
        try { Class.forName("InitSemantics$ForNamedBoom"); } catch (ExceptionInInitializerError e) {
            System.out.println("forName EIIE " + e.getCause().getMessage());
        }
        try { Class.forName("InitSemantics$ForNamedBoom"); } catch (NoClassDefFoundError e) { System.out.println("forName NCDFE"); }
        System.out.println(StaticHolder.class.getField("shared").get(null));
        flush("reflective inherited static");
    }
}
