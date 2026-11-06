import fixture.access.base.AccessRulesBase;
import fixture.access.sub.AccessRulesSub;
import java.lang.reflect.Field;
import java.lang.reflect.Method;

public class AccessRules {
    private int own = 9;

    private static class Nested {
        private int inner = 11;
    }

    static String attempt(Field field, Object target) {
        try {
            return field.getName() + "=" + field.getInt(target);
        } catch (IllegalAccessException error) {
            return field.getName() + " denied: " + error.getMessage();
        }
    }

    public static void main(String[] args) throws Throwable {
        AccessRulesBase plain = new AccessRulesBase();
        for (String name : new String[] {"privateValue", "packageValue", "protectedValue", "publicValue"}) {
            System.out.println("outside " + attempt(AccessRulesBase.class.getDeclaredField(name), plain));
        }
        Method method = AccessRulesBase.class.getDeclaredMethod("protectedMethod");
        try {
            method.invoke(plain);
        } catch (IllegalAccessException error) {
            System.out.println("outside method denied: " + error.getMessage());
        }
        System.out.println("self " + attempt(AccessRules.class.getDeclaredField("own"), new AccessRules()));
        Field inner = Nested.class.getDeclaredField("inner");
        System.out.println("nested " + attempt(inner, new Nested()));
        System.out.println(inner.isAccessible());
        inner.setAccessible(true);
        System.out.println("nested forced " + attempt(inner, new Nested()));
        Field publicField = AccessRulesBase.class.getField("publicValue");
        publicField.setInt(plain, 12);
        System.out.println(publicField.getInt(plain));
        Field privateField = AccessRulesBase.class.getDeclaredField("privateValue");
        try {
            privateField.setInt(plain, 13);
        } catch (IllegalAccessException error) {
            System.out.println("set denied: " + error.getMessage());
        }
        Field finalField = AccessRulesBase.class.getField("finalValue");
        try {
            finalField.setInt(plain, 16);
        } catch (IllegalAccessException error) {
            System.out.println("final denied: " + error.getMessage());
        }
        finalField.setAccessible(true);
        Field finalStatic = AccessRulesBase.class.getField("FINAL_STATIC");
        finalStatic.setAccessible(true);
        try {
            finalStatic.set(null, Integer.valueOf(18));
        } catch (IllegalAccessException error) {
            System.out.println("static final denied: " + error.getMessage());
        }
        try {
            finalField.set(plain, "text");
        } catch (IllegalArgumentException error) {
            System.out.println("wrong type: " + error.getMessage());
        }
        AccessRulesSub.run();
    }
}
