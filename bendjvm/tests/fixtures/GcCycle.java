public class GcCycle {
    static final class Pair {
        Pair other;
        int mark;
    }

    public static void main(String[] args) {
        int total = 0;
        for (int round = 0; round < 800; round++) {
            Pair a = new Pair();
            Pair b = new Pair();
            a.other = b;
            b.other = a;
            b.mark = round;
            total += a.other.mark;
        }
        Pair survivor = new Pair();
        survivor.mark = 12345;
        for (int i = 0; i < 500; i++) {
            new Pair();
        }
        System.out.println(total);
        System.out.println(survivor.mark);
    }
}
