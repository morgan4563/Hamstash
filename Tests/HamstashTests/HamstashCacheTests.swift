// HamstashCacheTests.swift

import Testing
import Foundation
@testable import Hamstash

// MARK: - 기본 동작

@Suite("HamstashCache - 기본 동작")
struct HamstashCacheBasicTests {

    @Test("LRU 정책으로 store/value가 동작한다")
    func lruPolicy() {
        let cache = HamstashCache<String, Int>(policy: .lru, capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
        #expect(cache.count == 1)
        #expect(cache.capacity == 3)
    }

    @Test("LFU 정책으로 동작한다")
    func lfuPolicy() {
        let cache = HamstashCache<String, Int>(policy: .lfu, capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("FIFO 정책으로 동작한다")
    func fifoPolicy() {
        let cache = HamstashCache<String, Int>(policy: .fifo, capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("TTL 정책으로 동작한다")
    func ttlPolicy() {
        let cache = HamstashCache<String, Int>(policy: .ttl(duration: 60), capacity: 3)
        cache.store(100, forKey: "A")

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("TTL 개별 ttl 지정이 동작한다")
    func ttlCustomExpiry() {
        let cache = HamstashCache<String, Int>(policy: .ttl(duration: 60), capacity: 3)
        cache.store(100, forKey: "A", ttl: 30)

        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("TTL이 아닌 정책에서 ttl 파라미터를 써도 크래시하지 않는다")
    func ttlParamOnNonTTLPolicy() {
        let cache = HamstashCache<String, Int>(policy: .lru, capacity: 3)
        cache.store(100, forKey: "A", ttl: 30)

        // ttl이 무시되고 일반 store로 동작
        #expect(cache.value(forKey: "A") == 100)
    }

    @Test("remove와 removeAll이 동작한다")
    func removeOperations() {
        let cache = HamstashCache<String, Int>(policy: .lru, capacity: 3)
        cache.store(1, forKey: "A")
        cache.store(2, forKey: "B")

        cache.remove(forKey: "A")
        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.count == 1)

        cache.removeAll()
        #expect(cache.count == 0)
    }
}

// MARK: - 동시성 안전 테스트

@Suite("HamstashCache - 동시성 안전")
struct HamstashCacheConcurrencyTests {

    @Test("여러 스레드에서 동시에 store해도 크래시하지 않는다")
    func concurrentStore() async {
        let cache = HamstashCache<Int, Int>(policy: .lru, capacity: 1000)

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<10 {
                group.addTask {
                    for i in 0..<100 {
                        let key = taskIndex * 100 + i
                        cache.store(key, forKey: key)
                    }
                }
            }
        }

        #expect(cache.count <= 1000)
        #expect(cache.count > 0)
    }

    @Test("여러 스레드에서 동시에 store + value해도 크래시하지 않는다")
    func concurrentStoreAndRetrieve() async {
        let cache = HamstashCache<Int, Int>(policy: .lru, capacity: 500)

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<200 {
                        cache.store(i, forKey: taskIndex * 200 + i)
                    }
                }
            }

            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<200 {
                        _ = cache.value(forKey: taskIndex * 200 + i)
                    }
                }
            }
        }

        #expect(cache.count <= 500)
    }

    @Test("여러 스레드에서 동시에 store + remove해도 크래시하지 않는다")
    func concurrentStoreAndRemove() async {
        let cache = HamstashCache<Int, Int>(policy: .lru, capacity: 500)

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<200 {
                        cache.store(i, forKey: taskIndex * 200 + i)
                    }
                }
            }

            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<200 {
                        cache.remove(forKey: taskIndex * 200 + i)
                    }
                }
            }
        }

        #expect(cache.count >= 0)
    }

    @Test("LFU에서 동시 접근해도 크래시하지 않는다")
    func concurrentLFU() async {
        let cache = HamstashCache<Int, Int>(policy: .lfu, capacity: 500)

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<10 {
                group.addTask {
                    for i in 0..<100 {
                        let key = taskIndex * 100 + i
                        cache.store(key, forKey: key)
                        _ = cache.value(forKey: key)
                    }
                }
            }
        }

        #expect(cache.count <= 500)
    }

    @Test("eviction이 동시에 발생해도 크래시하지 않는다")
    func concurrentEviction() async {
        let cache = HamstashCache<Int, Int>(policy: .lru, capacity: 10)

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<10 {
                group.addTask {
                    for i in 0..<100 {
                        let key = taskIndex * 100 + i
                        cache.store(key, forKey: key)
                        _ = cache.value(forKey: key)
                    }
                }
            }
        }

        #expect(cache.count <= 10)
        #expect(cache.count > 0)
    }
}
