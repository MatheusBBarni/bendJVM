public class GcChurn {
    static final class Node {
        final int value;
        final Node next;

        Node(int value, Node next) {
            this.value = value;
            this.next = next;
        }
    }

    public static void main(String[] args) {
        Node keep = new Node(7, null);
        int sum = 0;
        for (int i = 0; i < 3000; i++) {
            Node temporary = new Node(i, keep);
            sum += temporary.next.value;
        }
        System.out.println(keep.value);
        System.out.println(sum);
    }
}
