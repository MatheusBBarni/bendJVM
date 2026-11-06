package fixture.access.sub;

import fixture.access.base.AccessRulesBase;
import java.lang.invoke.MethodHandle;
import java.lang.invoke.MethodHandles;
import java.lang.invoke.MethodType;
import java.lang.reflect.Constructor;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class AccessRulesSub extends AccessRulesBase {
    public AccessRulesSub() {
        super(7);
    }

    static String attempt(Field field, Object target) {
        try {
            return field.getName() + "=" + field.getInt(target);
        } catch (IllegalAccessException error) {
            return field.getName() + " denied: " + error.getMessage();
        }
    }

    static String attempt(Method method, Object target) {
        try {
            return method.getName() + "=" + method.invoke(target);
        } catch (IllegalAccessException error) {
            return method.getName() + " denied: " + error.getMessage();
        } catch (Exception error) {
            return method.getName() + " failed: " + error;
        }
    }

    static String handle(String label, Lookup action) {
        try {
            MethodHandle handle = action.find();
            return label + " found " + handle.type();
        } catch (IllegalAccessException error) {
            String message = error.getMessage();
            int from = message.indexOf(", from ");
            return label + " denied: " + (from < 0 ? message : message.substring(0, from));
        } catch (ReflectiveOperationException error) {
            return label + " missing: " + error.getClass().getName();
        }
    }

    interface Lookup {
        MethodHandle find() throws ReflectiveOperationException;
    }

    public static void run() throws Throwable {
        Class<?> base = AccessRulesBase.class;
        AccessRulesBase plain = new AccessRulesBase();
        AccessRulesSub sub = new AccessRulesSub();
        for (String name : new String[] {"privateValue", "packageValue", "protectedValue", "publicValue"}) {
            Field field = base.getDeclaredField(name);
            System.out.println("sub/plain " + attempt(field, plain));
            System.out.println("sub/sub " + attempt(field, sub));
        }
        System.out.println("sub/static " + attempt(base.getDeclaredField("protectedStatic"), null));
        for (String name : new String[] {"privateMethod", "packageMethod", "protectedMethod", "publicMethod"}) {
            Method method = base.getDeclaredMethod(name);
            System.out.println("sub/plain " + attempt(method, plain));
            System.out.println("sub/sub " + attempt(method, sub));
        }
        System.out.println("sub/static " + attempt(base.getDeclaredMethod("protectedStaticMethod"), null));
        Constructor<?> seeded = base.getDeclaredConstructor(int.class);
        try {
            seeded.newInstance(Integer.valueOf(8));
            System.out.println("sub protected constructor allowed");
        } catch (IllegalAccessException error) {
            System.out.println("sub protected constructor denied: " + error.getMessage());
        }
        seeded.setAccessible(true);
        System.out.println("sub protected constructor forced " + ((AccessRulesBase) seeded.newInstance(Integer.valueOf(8))).publicValue);

        Object hidden = AccessRulesBase.packageOnly();
        Field visible = hidden.getClass().getDeclaredField("visible");
        System.out.println("sub/hidden " + attempt(visible, hidden));
        System.out.println("sub/hidden " + attempt(hidden.getClass().getDeclaredMethod("visibleMethod"), hidden));
        try {
            hidden.getClass().newInstance();
            System.out.println("sub hidden newInstance allowed");
        } catch (IllegalAccessException error) {
            System.out.println("sub hidden newInstance denied: " + error.getMessage());
        }
        visible.setAccessible(true);
        System.out.println("sub/hidden forced " + attempt(visible, hidden));

        MethodHandles.Lookup lookup = MethodHandles.lookup();
        MethodType intType = MethodType.methodType(int.class);
        System.out.println(handle("mh private", () -> lookup.findVirtual(base, "privateMethod", intType)));
        System.out.println(handle("mh package", () -> lookup.findVirtual(base, "packageMethod", intType)));
        System.out.println(handle("mh protected", () -> lookup.findVirtual(base, "protectedMethod", intType)));
        System.out.println(handle("mh public", () -> lookup.findVirtual(base, "publicMethod", intType)));
        System.out.println(handle("mh protected static", () -> lookup.findStatic(base, "protectedStaticMethod", intType)));
        System.out.println(handle("mh private getter", () -> lookup.findGetter(base, "privateValue", int.class)));
        System.out.println(handle("mh protected getter", () -> lookup.findGetter(base, "protectedValue", int.class)));
        System.out.println(handle("mh protected constructor", () -> lookup.findConstructor(base, MethodType.methodType(void.class, int.class))));
        System.out.println(handle("mh hidden", () -> lookup.findVirtual(hidden.getClass(), "visibleMethod", intType)));
        System.out.println(handle("mh private static", () -> lookup.findStatic(base, "privateStaticMethod", intType)));
        System.out.println(handle("mh private static getter", () -> lookup.findStaticGetter(base, "privateStatic", int.class)));
        System.out.println(handle("mh static as virtual", () -> lookup.findVirtual(base, "protectedStaticMethod", intType)));
        System.out.println(handle("mh virtual as static", () -> lookup.findStatic(base, "publicMethod", intType)));
        System.out.println(handle("mh static field as instance", () -> lookup.findGetter(base, "protectedStatic", int.class)));
        System.out.println(handle("mh instance field as static", () -> lookup.findStaticGetter(base, "publicValue", int.class)));
        MethodHandle narrowed = lookup.findVirtual(base, "protectedMethod", intType);
        System.out.println((int) narrowed.invoke(sub));
        try {
            System.out.println((int) narrowed.invoke(plain));
        } catch (ClassCastException error) {
            System.out.println("narrowed receiver: " + error.getMessage());
        }
        MethodHandles.Lookup publicOnly = lookup.in(fixture.access.base.AccessRulesBase.class);
        System.out.println((publicOnly.lookupModes() & 15) + " " + (lookup.lookupModes() & 15));
        System.out.println(handle("public lookup protected", () -> publicOnly.findVirtual(base, "protectedMethod", intType)));
        System.out.println(handle("public lookup public", () -> publicOnly.findVirtual(base, "publicMethod", intType)));
    }
}
