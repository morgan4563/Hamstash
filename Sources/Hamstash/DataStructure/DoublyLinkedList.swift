// DoublyLinkedList.swift
// LRU, LFU, FIFO에서 사용하는 이중 연결 리스트 직접 구현

/// 이중 연결 리스트의 노드
///
/// 각 노드는 키-값 쌍을 저장하며, 이전/다음 노드에 대한 참조를 가진다.
/// class(참조 타입)를 사용하는 이유: Dictionary에서 노드를 직접 참조해 O(1) 접근을 가능하게 하기 위함.
final class Node<Key: Hashable & Sendable, Value: Sendable> {
    let key: Key
    var value: Value
    var prev: Node?
    var next: Node?

    /// LFU에서 사용하는 접근 빈도
    var frequency: Int

    init(key: Key, value: Value, frequency: Int = 1) {
        self.key = key
        self.value = value
        self.frequency = frequency
    }
}

/// 이중 연결 리스트
///
/// head ↔ 실제노드들 ↔ tail 구조. (Optional 기반, 센티넬 노드 없음)
///
/// - 시간복잡도: 삽입 O(1), 삭제 O(1), head/tail 접근 O(1)
/// - LRU에서: head 쪽 = 가장 최근, tail 쪽 = 가장 오래된 항목
struct DoublyLinkedList<Key: Hashable & Sendable, Value: Sendable> {

    /// 가장 최근 노드 (맨 앞)
    private var head: Node<Key, Value>?

    /// 가장 오래된 노드 (맨 뒤)
    private var tail: Node<Key, Value>?

    /// 리스트에 저장된 실제 노드 수
    private(set) var count: Int = 0

    init() { }

    /// 리스트의 맨 앞(head)에 노드를 추가한다. O(1)
    /// - Parameter node: 추가할 노드
    mutating func addToHead(_ node: Node<Key, Value>) {
        node.prev = nil
        node.next = head
        head?.prev = node
        head = node

        // 리스트가 비어있었으면 tail도 설정
        if tail == nil { tail = node }
        count += 1
    }

    /// 리스트에서 노드를 제거한다. O(1)
    /// - Parameter node: 제거할 노드 (리스트에 존재해야 함)
    mutating func remove(_ node: Node<Key, Value>) {
        // head/tail 경계 처리
        if node === head { head = node.next }
        if node === tail { tail = node.prev }

        node.prev?.next = node.next
        node.next?.prev = node.prev
        node.prev = nil
        node.next = nil
        count -= 1
    }

    /// tail 노드(가장 오래된 항목)를 제거하고 반환한다. O(1)
    /// 리스트가 비어있으면 nil 반환.
    /// - Returns: 제거된 노드
    mutating func removeTail() -> Node<Key, Value>? {
        guard let last = tail else { return nil }
        remove(last)
        return last
    }

    /// 노드를 맨 앞으로 이동시킨다 (최근 사용 갱신). O(1)
    /// - Parameter node: 이동할 노드
    mutating func moveToHead(_ node: Node<Key, Value>) {
        remove(node)
        addToHead(node)
    }

    /// 리스트가 비어있는지 여부
    var isEmpty: Bool { count == 0 }

    /// 모든 노드를 제거한다.
    /// Node가 class(참조 타입)이므로, 노드 간 prev/next 순환 참조를 끊어야 ARC가 메모리를 해제할 수 있다.
    mutating func removeAll() {
        var current = head
        while let node = current {
            let next = node.next
            node.prev = nil
            node.next = nil
            current = next
        }
        head = nil
        tail = nil
        count = 0
    }
}
