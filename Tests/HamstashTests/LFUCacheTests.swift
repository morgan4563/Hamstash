// LFUCacheTests.swift

import Testing
@testable import Hamstash

// MARK: - 기본 동작

@Suite("LFU Cache - 기본 동작")
struct LFUCacheBasicTests {

    @Test("저장 후 조회하면 값이 반환된다")
    func storeAndRetrieve() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("존재하지 않는 키를 조회하면 nil이 반환된다")
    func retrieveNonExistentKey() {
        var cache = LFUCache<String, Int>(capacity: 3)

        #expect(cache.value(forKey: "X") == nil)
    }

    @Test("같은 키에 다시 store하면 값이 갱신된다")
    func updateExistingKey() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.store(999, forKey: "A")

        #expect(cache.value(forKey: "A") == 999)
        #expect(cache.count == 1)
    }

    @Test("remove로 특정 키를 제거할 수 있다")
    func removeKey() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.count == 0)
    }

    @Test("removeAll 후 캐시가 비어있다")
    func removeAll() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")
        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }
}

// MARK: - LFU 제거 정책

@Suite("LFU Cache - 제거 정책")
struct LFUCacheEvictionTests {

    @Test("용량 초과 시 가장 적게 사용된 항목이 제거된다")
    func evictsLeastFrequentlyUsed() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A를 2번 더 조회 (빈도 3), C를 1번 더 조회 (빈도 2), B는 조회 안 함 (빈도 1)
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "C")

        // D를 넣으면 빈도가 가장 낮은 B가 제거되어야 함
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "B") == nil)  // 빈도 1 → 제거됨
        #expect(cache.value(forKey: "A") != nil)   // 빈도 3 → 살아남음
        #expect(cache.value(forKey: "C") != nil)   // 빈도 2 → 살아남음
    }

    @Test("빈도가 같으면 더 오래된 항목(LRU)이 제거된다")
    func tieBreakByLRU() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")  // 빈도 1, 먼저 들어옴
        cache.store(2, forKey: "B")  // 빈도 1, 나중에 들어옴
        cache.store(3, forKey: "C")  // 빈도 1, 가장 나중에 들어옴

        // 모두 빈도 1 → A가 가장 오래됨 → A가 제거되어야 함
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "A") == nil)  // 같은 빈도에서 가장 오래됨 → 제거
        #expect(cache.count == 3)
    }

    @Test("자주 조회한 항목은 eviction에서 살아남는다")
    func frequentAccessSurvives() {
        var cache = LFUCache<String, Int>(capacity: 2)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        // A를 여러 번 조회 (빈도 증가)
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")

        // C를 넣으면 빈도가 낮은 B가 제거
        cache.store(3, forKey: "C")

        #expect(cache.value(forKey: "A") != nil)  // 빈도 높아서 살아남음
        #expect(cache.value(forKey: "B") == nil)   // 빈도 낮아서 제거됨
    }

    @Test("연속 eviction이 올바르게 동작한다")
    func consecutiveEvictions() {
        var cache = LFUCache<String, Int>(capacity: 2)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        cache.store(3, forKey: "C")  // A 제거 (A, B 둘 다 빈도1이지만 A가 더 오래됨)
        #expect(cache.value(forKey: "A") == nil)

        cache.store(4, forKey: "D")  // B 제거 (B는 빈도1, C는 빈도1이지만 B가 더 오래됨)
        #expect(cache.value(forKey: "B") == nil)

        #expect(cache.count == 2)
    }
}

// MARK: - minFrequency 정합성

@Suite("LFU Cache - minFrequency 정합성")
struct LFUCacheMinFrequencyTests {

    @Test("새 노드 store 시 minFrequency가 항상 1로 리셋된다")
    func minFrequencyResetsOnNewStore() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        // A를 여러 번 조회해서 빈도를 올림
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")

        // B를 새로 넣으면 minFrequency는 1이어야 함
        cache.store(2, forKey: "B")

        // C를 넣어도 용량 안에 있으므로 eviction 없음
        cache.store(3, forKey: "C")

        // D를 넣으면 → 빈도 1인 것 중 가장 오래된 B가 제거되어야 함
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "B") == nil)  // B 제거
        #expect(cache.value(forKey: "A") != nil)   // A는 빈도 높아서 살아남
    }

    @Test("remove(forKey:)로 minFrequency 버킷이 비어도 다음 store가 정상 동작한다")
    func removeMinFrequencyBucketThenStore() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")  // 빈도 1
        cache.store(2, forKey: "B")  // 빈도 1
        _ = cache.value(forKey: "B") // B 빈도 2

        // A 제거 → 빈도 1 버킷이 비어짐 → minFrequency 갱신 필요
        cache.remove(forKey: "A")
        #expect(cache.count == 1)

        // 새로 store → eviction이 정상 동작해야 함
        cache.store(3, forKey: "C")
        cache.store(4, forKey: "D")

        // 용량 3이니까 B, C, D 모두 있어야 함
        #expect(cache.value(forKey: "B") != nil)
        #expect(cache.value(forKey: "C") != nil)
        #expect(cache.value(forKey: "D") != nil)
        #expect(cache.count == 3)
    }

    @Test("remove로 유일한 항목을 지워도 다시 store할 수 있다")
    func removeOnlyItemThenStore() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.count == 0)

        cache.store(2, forKey: "B")
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }

    @Test("incrementFrequency 후 빈 버킷이 제거되고 minFrequency가 올바르게 갱신된다")
    func incrementFrequencyUpdatesMinFrequency() {
        var cache = LFUCache<String, Int>(capacity: 2)
        cache.store(1, forKey: "A")  // 빈도 1
        cache.store(2, forKey: "B")  // 빈도 1

        // 둘 다 빈도를 올림
        _ = cache.value(forKey: "A")  // A 빈도 2
        _ = cache.value(forKey: "B")  // B 빈도 2

        // 이제 빈도 1 버킷은 비었고, minFrequency는 2여야 함
        // C를 넣으면 → eviction 시 빈도 2 버킷에서 제거해야 함
        cache.store(3, forKey: "C")  // C 빈도 1, eviction: 빈도 2 중 오래된 A 제거

        // C가 들어올 때 minFrequency=1(새 노드)이므로 eviction 대상은 빈도가 낮은 것
        // 하지만 C를 넣기 전에는 minFrequency=2였고, eviction 시 A가 제거됨
        // 그 후 C(빈도 1)가 들어와서 minFrequency=1로 리셋

        // A가 제거되고 B, C가 남아야 함
        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") != nil)
        #expect(cache.value(forKey: "C") != nil)
    }
}

// MARK: - Edge Case

@Suite("LFU Cache - Edge Case")
struct LFUCacheEdgeCaseTests {

    @Test("capacity=0이면 store해도 아무것도 저장되지 않는다")
    func capacityZero() {
        var cache = LFUCache<String, Int>(capacity: 0)
        cache.store(1, forKey: "A")

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("capacity=1이면 항상 마지막 저장 항목만 남는다")
    func capacityOne() {
        var cache = LFUCache<String, Int>(capacity: 1)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }

    @Test("빈 캐시에서 remove를 호출해도 크래시하지 않는다")
    func removeFromEmptyCache() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.remove(forKey: "X")

        #expect(cache.count == 0)
    }

    @Test("removeAll 후 다시 store할 수 있다")
    func storeAfterRemoveAll() {
        var cache = LFUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")
        cache.removeAll()

        cache.store(2, forKey: "B")
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }
}
