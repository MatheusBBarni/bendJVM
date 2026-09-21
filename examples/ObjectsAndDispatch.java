public class ObjectsAndDispatch {
    int value() {
        return 10;
    }

    public static void main(String[] args) {
        ObjectsAndDispatch plain = new ObjectsAndDispatch();
        ObjectsAndDispatch offset = new OffsetBox();
        System.out.println(plain.value());
        System.out.println(offset.value());
        System.out.println(new Counter(3).next());
        System.out.println(plain.equals(plain));
        System.out.println(plain.equals(offset));
    }
}

class OffsetBox extends ObjectsAndDispatch {
    int value() {
        return 11;
    }
}

class Counter {
    private int value;

    Counter(int start) {
        value = start;
    }

    int next() {
        value += 1;
        return value;
    }
}
