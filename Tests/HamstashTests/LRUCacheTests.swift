// LRUCacheTests.swift

import Testing
@testable import Hamstash

// MARK: - 기본 동작

@Suite("LRU Cache - 기본 동작")
struct LRUCacheBasicTests {

    @Test("저장 후 조회하면 값이 반환된다")
    func storeAndRetrieve() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("존재하지 않는 키를 조회하면 nil이 반환된다")
    func retrieveNonExistentKey() {
        var cache = LRUCache<String, Int>(capacity: 3)

        #expect(cache.value(forKey: "X") == nil)
    }

    @Test("같은 키에 다시 store하면 값이 갱신된다")
    func updateExistingKey() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.store(999, forKey: "A")

        #expect(cache.value(forKey: "A") == 999)
        #expect(cache.count == 1)
    }

    @Test("remove로 특정 키를 제거할 수 있다")
    func removeKey() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.count == 0)
    }

    @Test("removeAll 후 캐시가 비어있다")
    func removeAll() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")
        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == nil)
        #expect(cache.value(forKey: "C") == nil)
    }

    @Test("count가 저장 항목 수와 일치한다")
    func countAccuracy() {
        var cache = LRUCache<String, Int>(capacity: 5)
        #expect(cache.count == 0)

        cache.store(1, forKey: "A")
        #expect(cache.count == 1)

        cache.store(2, forKey: "B")
        #expect(cache.count == 2)

        cache.remove(forKey: "A")
        #expect(cache.count == 1)
    }
}

// MARK: - LRU 제거 정책

@Suite("LRU Cache - 제거 정책")
struct LRUCacheEvictionTests {

    @Test("용량 초과 시 가장 오래 사용하지 않은 항목이 제거된다")
    func evictsLeastRecentlyUsed() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A가 가장 오래됨 → D를 넣으면 A가 제거되어야 함
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.value(forKey: "C") == 3)
        #expect(cache.value(forKey: "D") == 4)
        #expect(cache.count == 3)
    }

    @Test("조회하면 최근 사용으로 갱신되어 제거 대상에서 빠진다")
    func accessPreventsEviction() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A를 조회 → A가 최근 사용됨 → 이제 B가 가장 오래됨
        _ = cache.value(forKey: "A")
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "A") == 1)   // 살아남음
        #expect(cache.value(forKey: "B") == nil)  // 제거됨
    }

    @Test("같은 키에 store해도 최근 사용으로 갱신된다")
    func reStorePreventsEviction() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A를 다시 store → A가 최근 사용됨 → B가 가장 오래됨
        cache.store(100, forKey: "A")
        cache.store(4, forKey: "D")

        #expect(cache.value(forKey: "A") == 100)
        #expect(cache.value(forKey: "B") == nil)
    }

    @Test("연속 eviction이 올바르게 동작한다")
    func consecutiveEvictions() {
        var cache = LRUCache<String, Int>(capacity: 2)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        cache.store(3, forKey: "C")  // A 제거
        #expect(cache.value(forKey: "A") == nil)

        cache.store(4, forKey: "D")  // B 제거
        #expect(cache.value(forKey: "B") == nil)

        #expect(cache.value(forKey: "C") == 3)
        #expect(cache.value(forKey: "D") == 4)
        #expect(cache.count == 2)
    }
}

// MARK: - Edge Case

@Suite("LRU Cache - Edge Case")
struct LRUCacheEdgeCaseTests {

    @Test("capacity=0이면 store해도 아무것도 저장되지 않는다")
    func capacityZero() {
        var cache = LRUCache<String, Int>(capacity: 0)
        cache.store(1, forKey: "A")

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("capacity=1이면 항상 마지막 저장 항목만 남는다")
    func capacityOne() {
        var cache = LRUCache<String, Int>(capacity: 1)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }

    @Test("빈 캐시에서 remove를 호출해도 크래시하지 않는다")
    func removeFromEmptyCache() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.remove(forKey: "X")  // 크래시 없어야 함

        #expect(cache.count == 0)
    }

    @Test("removeAll 후 다시 store할 수 있다")
    func storeAfterRemoveAll() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.removeAll()

        cache.store(3, forKey: "C")
        #expect(cache.value(forKey: "C") == 3)
        #expect(cache.count == 1)
    }

    @Test("같은 키를 중복 store해도 count가 증가하지 않는다")
    func duplicateStoreDoesNotIncreaseCount() {
        var cache = LRUCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "A")
        cache.store(3, forKey: "A")

        #expect(cache.count == 1)
    }
}
