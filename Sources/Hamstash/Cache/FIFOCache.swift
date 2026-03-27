// FIFOCache.swift
// First In First Out — 먼저 들어온 항목부터 제거

/// FIFO 캐시
///
/// **자료구조**: DoublyLinkedList(큐 역할) + Dictionary
/// - 삽입은 head에, 제거는 tail에서 → 선입선출
/// - LRU와 달리 조회 시 순서를 갱신하지 않음
///
/// **시간복잡도**: store O(1), value O(1), remove O(1)
///
/// **적합한 사용 시나리오**:
/// - 순서대로 처리해야 하는 데이터 (타임라인, 로그 등)
/// - 접근 패턴과 무관하게 공정한 제거가 필요한 경우
///
/// **단점**:
/// - 자주 사용하는 항목도 오래되면 무조건 제거됨
/// - 접근 패턴을 전혀 반영하지 않아 캐시 적중률이 낮을 수 있음
struct FIFOCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    private var map: [Key: Node<Key, Value>] = [:]
    private var list = DoublyLinkedList<Key, Value>()

    let capacity: Int

    /// - Parameter capacity: 최대 저장 항목 수
    init(capacity: Int) {
        self.capacity = capacity
    }
}

extension FIFOCache: CachePolicy {

    var count: Int { map.count }

    mutating func store(_ value: Value, forKey key: Key) {
        // 이미 존재하면 값만 갱신 (순서는 유지 — FIFO이므로)
        if let existingNode = map[key] {
            existingNode.value = value
            return
        }

        // 용량 초과 시 가장 먼저 들어온 항목(tail) 제거
        if map.count >= capacity {
            if let evicted = list.removeTail() {
                map.removeValue(forKey: evicted.key)
            }
        }

        let newNode = Node(key: key, value: value)
        list.addToHead(newNode)
        map[key] = newNode
    }

    mutating func value(forKey key: Key) -> Value? {
        // FIFO는 조회 시 순서를 갱신하지 않음 (LRU와의 차이점)
        map[key]?.value
    }

    mutating func remove(forKey key: Key) {
        guard let node = map[key] else { return }
        list.remove(node)
        map.removeValue(forKey: key)
    }

    mutating func removeAll() {
        map.removeAll()
        list.removeAll()
    }
}
