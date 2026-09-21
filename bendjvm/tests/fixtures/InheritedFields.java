public class InheritedFields {
    public static void main(String[] args) {
        FieldChild child = new FieldChild();
        FieldParent parent = child;
        parent.value = 11; child.value = 29; child.other = 7;
        System.out.println(parent.value); System.out.println(child.value);
        System.out.println(child.readParent()); System.out.println(parent.read());
        System.out.println(child.other);
    }
}
class FieldParent {
    int value;
    int read() { return value; }
}
class FieldChild extends FieldParent {
    int value;
    int other;
    int readParent() { return super.value; }
    int read() { return super.read() + value; }
}
