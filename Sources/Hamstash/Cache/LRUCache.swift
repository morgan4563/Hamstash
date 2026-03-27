// LRUCache.swift
// Least Recently Used — 가장 오래 사용하지 않은 항목부터 제거

/// LRU 캐시
///
/// **자료구조**: DoublyLinkedList + Dictionary
/// - Dictionary: 키로 노드를 O(1) 조회
/// - DoublyLinkedList: 사용 순서를 O(1)로 관리 (head = 최근, tail = 오래된)
///
/// **시간복잡도**: store O(1), value O(1), remove O(1)
///
/// **적합한 사용 시나리오**:
/// - 최근 본 이미지를 다시 볼 확률이 높은 경우 (SNS 피드, 채팅 등)
/// - 가장 범용적인 캐시 정책으로 대부분의 상황에서 무난하게 사용 가능
///
/// **단점**:
/// - 자주 사용하는 항목이라도 한동안 접근하지 않으면 제거될 수 있음
struct LRUCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    /// 키 → 노드 매핑 (O(1) 조회용)
    private var map: [Key: Node<Key, Value>] = [:]

    /// 사용 순서를 관리하는 이중 연결 리스트
    private var list = DoublyLinkedList<Key, Value>()

    let capacity: Int

    /// LRU 캐시를 생성한다.
    /// - Parameter capacity: 최대 저장 항목 수
    init(capacity: Int) {
        self.capacity = capacity
    }
}

extension LRUCache: CachePolicy {

    var count: Int { map.count }

    mutating func store(_ value: Value, forKey key: Key) {
        // 이미 존재하면 값 갱신 후 맨 앞으로 이동
        if let existingNode = map[key] {
            existingNode.value = value
            list.moveToHead(existingNode)
            return
        }

        // 용량 초과 시 가장 오래된 항목(tail) 제거
        if map.count >= capacity {
            if let evicted = list.removeTail() {
                map.removeValue(forKey: evicted.key)
            }
        }

        // 새 노드 생성 후 맨 앞에 추가
        let newNode = Node(key: key, value: value)
        list.addToHead(newNode)
        map[key] = newNode
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let node = map[key] else { return nil }
        // 접근했으므로 최근 사용으로 갱신
        list.moveToHead(node)
        return node.value
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
