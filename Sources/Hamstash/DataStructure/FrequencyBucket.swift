// FrequencyBucket.swift
// LFU에서 동일 빈도의 노드들을 관리하는 버킷

/// 빈도 버킷
///
/// 같은 접근 빈도를 가진 노드들을 DoublyLinkedList로 관리한다.
/// 동일 빈도 내에서는 LRU 방식으로 제거 (tail이 가장 오래된 항목).
///
/// 예: frequency=3인 버킷에 A, B, C가 있으면
///     head ↔ C(최근) ↔ B ↔ A(오래된) ↔ tail
///     제거 시 A가 먼저 나간다.
struct FrequencyBucket<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    let frequency: Int
    var list = DoublyLinkedList<Key, Value>()

    init(frequency: Int) {
        self.frequency = frequency
    }

    /// 버킷에 노드를 추가한다 (맨 앞 = 최근).
    mutating func add(_ node: Node<Key, Value>) {
        list.addToHead(node)
    }

    /// 버킷에서 노드를 제거한다.
    mutating func remove(_ node: Node<Key, Value>) {
        list.remove(node)
    }

    /// 가장 오래된 노드(tail)를 제거하고 반환한다.
    mutating func removeLRU() -> Node<Key, Value>? {
        list.removeTail()
    }

    var isEmpty: Bool { list.isEmpty }
    var count: Int { list.count }
}
