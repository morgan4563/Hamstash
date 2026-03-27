// TTLCacheTests.swift

import Testing
import Foundation
@testable import Hamstash

// MARK: - 기본 동작

@Suite("TTL Cache - 기본 동작")
struct TTLCacheBasicTests {

    @Test("저장 후 만료 전에 조회하면 값이 반환된다")
    func storeAndRetrieveBeforeExpiry() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("존재하지 않는 키를 조회하면 nil이 반환된다")
    func retrieveNonExistentKey() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)

        #expect(cache.value(forKey: "X") == nil)
    }

    @Test("같은 키에 다시 store하면 값과 만료 시각이 갱신된다")
    func updateExistingKey() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(100, forKey: "A")
        cache.store(999, forKey: "A")

        #expect(cache.value(forKey: "A") == 999)
        #expect(cache.count == 1)
    }

    @Test("remove로 특정 키를 제거할 수 있다")
    func removeKey() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(100, forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.count == 0)
    }

    @Test("removeAll 후 캐시가 비어있다")
    func removeAll() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")
        cache.removeAll()

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }
}

// MARK: - TTL 만료 동작

@Suite("TTL Cache - 만료 동작")
struct TTLCacheExpirationTests {

    @Test("만료 시간이 지나면 조회 시 nil이 반환된다 (Lazy Deletion)")
    func expiredItemReturnsNil() async throws {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 1)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)

        // 1.1초 대기 → 만료
        try await Task.sleep(for: .milliseconds(1100))

        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("만료된 항목 조회 후 count가 감소한다")
    func expiredItemReducesCount() async throws {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 1)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        #expect(cache.count == 2)

        try await Task.sleep(for: .milliseconds(1100))

        // A 조회 → 만료 삭제 → count 감소
        _ = cache.value(forKey: "A")
        #expect(cache.count == 1)  // B는 아직 조회 안 했으니 map에 남아있음
    }

    @Test("개별 TTL을 지정해서 저장할 수 있다")
    func customTTLPerItem() async throws {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(1, forKey: "short", ttl: 1)   // 1초 후 만료
        cache.store(2, forKey: "long", ttl: 60)    // 60초 후 만료

        try await Task.sleep(for: .milliseconds(1100))

        #expect(cache.value(forKey: "short") == nil)  // 만료
        #expect(cache.value(forKey: "long") == 2)      // 아직 유효
    }
}

// MARK: - 용량 초과

@Suite("TTL Cache - 용량 초과")
struct TTLCacheCapacityTests {

    @Test("용량 초과 시 만료 항목을 먼저 정리한다")
    func evictsExpiredFirst() async throws {
        var cache = TTLCache<String, Int>(capacity: 2, defaultTTL: 1)
        cache.store(1, forKey: "A")  // 1초 후 만료

        try await Task.sleep(for: .milliseconds(1100))

        cache.store(2, forKey: "B")  // 아직 용량 여유 (A가 만료라 count는 2지만)
        cache.store(3, forKey: "C")  // 용량 초과 → A(만료)가 정리됨

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.value(forKey: "C") == 3)
    }

    @Test("만료 항목이 없으면 가장 빨리 만료되는 항목이 제거된다")
    func evictsEarliestExpiring() {
        var cache = TTLCache<String, Int>(capacity: 2, defaultTTL: 60)
        cache.store(1, forKey: "A", ttl: 10)   // 10초 후 만료 (가장 빨리 만료)
        cache.store(2, forKey: "B", ttl: 60)   // 60초 후 만료

        cache.store(3, forKey: "C", ttl: 30)   // 용량 초과 → A(가장 빨리 만료)가 제거됨

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.value(forKey: "C") == 3)
    }
}

// MARK: - Edge Case

@Suite("TTL Cache - Edge Case")
struct TTLCacheEdgeCaseTests {

    @Test("capacity=0이면 store해도 아무것도 저장되지 않는다")
    func capacityZero() {
        var cache = TTLCache<String, Int>(capacity: 0, defaultTTL: 60)
        cache.store(1, forKey: "A")

        #expect(cache.count == 0)
        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("capacity=1이면 항상 마지막 저장 항목만 남는다")
    func capacityOne() {
        var cache = TTLCache<String, Int>(capacity: 1, defaultTTL: 60)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == 2)
    }

    @Test("defaultTTL=0으로 생성하면 1초로 보정된다")
    func defaultTTLZeroIsCorrected() {
        let cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 0)

        #expect(cache.defaultTTL == 1)
    }

    @Test("ttl=0으로 store하면 1초로 보정되어 즉시 만료되지 않는다")
    func ttlZeroIsCorrected() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(1, forKey: "A", ttl: 0)

        // 0이 1초로 보정되었으므로 즉시 조회하면 값이 있어야 함
        #expect(cache.value(forKey: "A") == 1)
    }

    @Test("빈 캐시에서 remove를 호출해도 크래시하지 않는다")
    func removeFromEmptyCache() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.remove(forKey: "X")

        #expect(cache.count == 0)
    }

    @Test("removeAll 후 다시 store할 수 있다")
    func storeAfterRemoveAll() {
        var cache = TTLCache<String, Int>(capacity: 3, defaultTTL: 60)
        cache.store(1, forKey: "A")
        cache.removeAll()

        cache.store(2, forKey: "B")
        #expect(cache.value(forKey: "B") == 2)
        #expect(cache.count == 1)
    }
}
