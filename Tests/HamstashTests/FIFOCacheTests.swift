// FIFOCacheTests.swift

import Testing
@testable import Hamstash

// MARK: - 기본 동작

@Suite("FIFO Cache - 기본 동작")
struct FIFOCacheBasicTests {

    @Test("저장 후 조회하면 값이 반환된다")
    func storeAndRetrieve() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("존재하지 않는 키를 조회하면 nil이 반환된다")
    func retrieveNonExistentKey() {
        var cache = FIFOCache<String, Int>(capacity: 3)

        #expect(cache.value(forKey: "X") == nil)
    }

    @Test("같은 키에 다시 store하면 값이 갱신된다")
    func updateExistingKey() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.store(999, forKey: "A")

        #expect(cache.value(forKey: "A") == 999)
        #expect(cache.count == 1)
    }

    @Test("remove로 특정 키를 제거할 수 있다")
    func removeKey() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(100, forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.count == 0)
    }

    @Test("removeAll 후 캐시가 비어있다")
    func removeAll() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")
        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }
}

// MARK: - FIFO 제거 정책

@Suite("FIFO Cache - 제거 정책")
struct FIFOCacheEvictionTests {

    @Test("용량 초과 시 먼저 들어온 항목이 제거된다")
    func evictsFirstIn() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")  // 1번째
        cache.store(2, forKey: "B")  // 2번째
        cache.store(3, forKey: "C")  // 3번째

        cache.store(4, forKey: "D")  // A가 제거되어야 함

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.value(forKey: "C") == 3)
        #expect(cache.value(forKey: "D") == 4)
    }

    @Test("조회해도 순서가 바뀌지 않는다 (LRU와의 핵심 차이)")
    func accessDoesNotChangeOrder() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")  // 1번째 (가장 오래됨)
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A를 아무리 많이 조회해도 순서 변경 없음
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")
        _ = cache.value(forKey: "A")

        cache.store(4, forKey: "D")

        // A는 먼저 들어왔으므로 제거됨 (조회 횟수 무관)
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("같은 키에 store해도 삽입 순서는 바뀌지 않는다")
    func reStoreDoesNotChangeOrder() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.store(3, forKey: "C")

        // A의 값만 갱신, 순서는 그대로
        cache.store(999, forKey: "A")
        cache.store(4, forKey: "D")

        // A가 여전히 가장 먼저 들어왔으므로 제거됨
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("연속 eviction이 올바르게 동작한다")
    func consecutiveEvictions() {
        var cache = FIFOCache<String, Int>(capacity: 2)
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

@Suite("FIFO Cache - Edge Case")
struct FIFOCacheEdgeCaseTests {

    @Test("capacity=0이면 store해도 아무것도 저장되지 않는다")
    func capacityZero() {
        var cache = FIFOCache<String, Int>(capacity: 0)
        cache.store(1, forKey: "A")

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("capacity=1이면 항상 마지막 저장 항목만 남는다")
    func capacityOne() {
        var cache = FIFOCache<String, Int>(capacity: 1)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }

    @Test("빈 캐시에서 remove를 호출해도 크래시하지 않는다")
    func removeFromEmptyCache() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.remove(forKey: "X")

        #expect(cache.count == 0)
    }

    @Test("removeAll 후 다시 store할 수 있다")
    func storeAfterRemoveAll() {
        var cache = FIFOCache<String, Int>(capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.removeAll()

        cache.store(3, forKey: "C")
        #expect(cache.value(forKey: "C") == 3)
        #expect(cache.count == 1)
    }
}
