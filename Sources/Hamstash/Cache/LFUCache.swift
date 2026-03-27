// LFUCache.swift
// Least Frequently Used — 가장 적게 사용된 항목부터 제거

/// LFU 캐시
///
/// **자료구조**: Dictionary(키→노드) + Dictionary(빈도→FrequencyBucket)
/// - 키 맵: 키로 노드를 O(1) 조회
/// - 빈도 맵: 빈도별 버킷에서 노드를 O(1) 관리
/// - minFrequency: 현재 최소 빈도를 추적해 제거 대상을 O(1)로 찾음
///
/// **시간복잡도**: store O(1), value O(1), remove O(1)
///
/// **적합한 사용 시나리오**:
/// - 인기 콘텐츠가 반복 노출되는 경우 (상품 목록, 프로필 이미지 등)
/// - 자주 쓰는 항목을 오래 유지하고 싶을 때
///
/// **단점**:
/// - 과거에 많이 쓰였지만 더 이상 안 쓰는 항목이 오래 남을 수 있음 (cache pollution)
/// - LRU보다 구현이 복잡함
struct LFUCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {

    /// 키 → 노드 매핑
    private var map: [Key: Node<Key, Value>] = [:]

    /// 빈도 → 해당 빈도의 노드들을 담은 버킷
    private var buckets: [Int: FrequencyBucket<Key, Value>] = [:]

    /// 현재 캐시 내 최소 접근 빈도 (제거 대상을 O(1)로 찾기 위함)
    private var minFrequency: Int = 1

    let capacity: Int

    /// - Parameter capacity: 최대 저장 항목 수
    init(capacity: Int) {
        self.capacity = capacity
    }

    /// 빈도 버킷을 가져오거나, 없으면 새로 생성한다.
    private mutating func bucket(for frequency: Int) -> FrequencyBucket<Key, Value> {
        if let existing = buckets[frequency] {
            return existing
        }
        let newBucket = FrequencyBucket<Key, Value>(frequency: frequency)
        buckets[frequency] = newBucket
        return newBucket
    }

    /// 노드의 빈도를 1 증가시키고, 기존 버킷에서 새 버킷으로 이동한다.
    private mutating func incrementFrequency(of node: Node<Key, Value>) {
        let oldFreq = node.frequency

        // 기존 빈도 버킷에서 제거
        buckets[oldFreq]?.remove(node)

        // 기존 버킷이 비었고, 그게 최소 빈도였으면 minFrequency 갱신
        if buckets[oldFreq]?.isEmpty == true {
            buckets.removeValue(forKey: oldFreq)
            if minFrequency == oldFreq {
                minFrequency = oldFreq + 1
            }
        }

        // 빈도 증가 후 새 버킷에 추가
        node.frequency = oldFreq + 1
        var newBucket = bucket(for: node.frequency)
        newBucket.add(node)
        buckets[node.frequency] = newBucket
    }
}

extension LFUCache: CachePolicy {

    var count: Int { map.count }

    mutating func store(_ value: Value, forKey key: Key) {
        guard capacity > 0 else { return }

        // 이미 존재하면 값 갱신 + 빈도 증가
        if let existingNode = map[key] {
            existingNode.value = value
            incrementFrequency(of: existingNode)
            return
        }

        // 용량 초과 시 최소 빈도 버킷에서 가장 오래된(LRU) 항목 제거
        if map.count >= capacity {
            if var minBucket = buckets[minFrequency],
               let evicted = minBucket.removeLRU() {
                map.removeValue(forKey: evicted.key)
                if minBucket.isEmpty {
                    buckets.removeValue(forKey: minFrequency)
                } else {
                    buckets[minFrequency] = minBucket
                }
            }
        }

        // 새 노드 생성 (빈도 1), 빈도 1 버킷에 추가
        let newNode = Node(key: key, value: value, frequency: 1)
        map[key] = newNode
        var firstBucket = bucket(for: 1)
        firstBucket.add(newNode)
        buckets[1] = firstBucket
        minFrequency = 1
    }

    mutating func value(forKey key: Key) -> Value? {
        guard let node = map[key] else { return nil }
        incrementFrequency(of: node)
        return node.value
    }

    mutating func remove(forKey key: Key) {
        guard let node = map[key] else { return }
        let freq = node.frequency
        buckets[freq]?.remove(node)
        if buckets[freq]?.isEmpty == true {
            buckets.removeValue(forKey: freq)
        }
        map.removeValue(forKey: key)
    }

    mutating func removeAll() {
        map.removeAll()
        buckets.removeAll()
        minFrequency = 1
    }
}
