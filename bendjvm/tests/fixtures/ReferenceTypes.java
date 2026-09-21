public class ReferenceTypes {
    public static void main(String[] args) {
        Object child = new TypeChild(); Object absent = null;
        System.out.println(child instanceof TypeParent); System.out.println(child instanceof TypeChild);
        System.out.println(child instanceof String); System.out.println(absent instanceof TypeParent);
        TypeParent parent = (TypeParent) child; System.out.println(parent.value());
        System.out.println((TypeChild) absent == null);
        Object[] values = new TypeParent[2]; values[0] = new TypeChild();
        System.out.println(values[0] instanceof TypeChild);
        try { values[1] = new Object(); } catch (ArrayStoreException e) { System.out.println(71); }
    }
}
class TypeParent { int value() { return 23; } }
class TypeChild extends TypeParent { int value() { return 41; } }
