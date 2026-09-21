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

public class ObjectsAndDispatch {
    public static void main(String[] args) {
        Counter counter = new Counter(10);
        System.out.println(counter.next());
        System.out.println(counter.next());
    }
}
