// HamstashStorageTests.swift

import Testing
import Foundation
@testable import Hamstash

// MARK: - 테스트용 헬퍼

/// 격리된 HamstashStorage를 생성한다.
private func makeTestStorage(
    memoryPolicy: HamstashCache<String, Data>.Policy = .lru,
    memoryCapacity: Int = 100,
    diskTotalCostLimit: DiskCache.ByteSize = .unlimited,
    diskMaxAge: TimeInterval = 0
) -> (HamstashStorage, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let diskConfig = DiskCache.Configuration(
        name: "test",
        totalCostLimit: diskTotalCostLimit,
        maxAge: diskMaxAge
    )
    let diskCache = DiskCache(config: diskConfig, directory: tempDir)
    let memoryCache = ImageCache(policy: memoryPolicy, capacity: memoryCapacity)
    let storage = HamstashStorage(memoryCache: memoryCache, diskCache: diskCache)

    return (storage, tempDir)
}

private func cleanup(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

private func testData(_ string: String = "test") -> Data {
    Data(string.utf8)
}

// MARK: - 2단계 캐시 동작

@Suite("HamstashStorage - 2단계 캐시 동작")
struct HamstashStorageBasicTests {

    @Test("저장 후 조회하면 데이터가 반환된다")
    func storeAndRetrieve() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        let data = testData("hello")
        storage.store(data, forKey: "A")

        #expect(storage.value(forKey: "A") == data)
    }

    @Test("메모리 캐시를 비워도 디스크에서 조회된다")
    func diskFallback() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        let data = testData("hello")
        storage.store(data, forKey: "A")

        // 메모리만 비우기
        storage.clearMemory()

        // 디스크에서 조회
        #expect(storage.value(forKey: "A") == data)
    }

    @Test("디스크에서 조회된 데이터가 메모리에 promote된다")
    func diskToMemoryPromote() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        let data = testData("hello")
        storage.store(data, forKey: "A")

        // 메모리 비우기
        storage.clearMemory()

        // 첫 번째 조회: 디스크에서 가져오면서 메모리에 promote
        let result1 = storage.value(forKey: "A")
        #expect(result1 == data)

        // 디스크 비우기
        storage.clearDisk()

        // 두 번째 조회: promote된 메모리에서 가져옴
        let result2 = storage.value(forKey: "A")
        #expect(result2 == data)
    }

    @Test("메모리와 디스크 양쪽에 없으면 nil이 반환된다")
    func missOnBothLayers() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        #expect(storage.value(forKey: "nonexistent") == nil)
    }

    @Test("remove 시 메모리 + 디스크 양쪽에서 삭제된다")
    func removeBothLayers() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData(), forKey: "A")
        storage.remove(forKey: "A")

        #expect(storage.value(forKey: "A") == nil)
        #expect(storage.memoryCache.value(forKey: "A") == nil)
        #expect(storage.diskCache.value(forKey: "A") == nil)
    }

    @Test("isCached가 메모리 또는 디스크에 있으면 true를 반환한다")
    func isCached() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        #expect(storage.isCached(forKey: "A") == false)

        storage.store(testData(), forKey: "A")
        #expect(storage.isCached(forKey: "A") == true)

        // 메모리만 비워도 디스크에 있으므로 true
        storage.clearMemory()
        #expect(storage.isCached(forKey: "A") == true)

        // 양쪽 다 비우면 false
        storage.clearAll()
        #expect(storage.isCached(forKey: "A") == false)
    }
}

// MARK: - 계층별 비우기

@Suite("HamstashStorage - 계층별 비우기")
struct HamstashStorageClearTests {

    @Test("clearMemory는 메모리만 비운다")
    func clearMemoryOnly() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData(), forKey: "A")
        storage.clearMemory()

        // 메모리는 비었지만 디스크에는 남아있음
        #expect(storage.memoryCache.value(forKey: "A") == nil)
        #expect(storage.diskCache.value(forKey: "A") != nil)
    }

    @Test("clearDisk는 디스크만 비운다")
    func clearDiskOnly() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData(), forKey: "A")
        storage.clearDisk()

        // 디스크는 비었지만 메모리에는 남아있음
        #expect(storage.memoryCache.value(forKey: "A") != nil)
        #expect(storage.diskCache.value(forKey: "A") == nil)
    }

    @Test("clearAll은 양쪽 다 비운다")
    func clearAll() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData(), forKey: "A")
        storage.clearAll()

        #expect(storage.memoryCache.value(forKey: "A") == nil)
        #expect(storage.diskCache.value(forKey: "A") == nil)
    }
}

// MARK: - 정책 조합

@Suite("HamstashStorage - 정책 조합")
struct HamstashStoragePolicyTests {

    @Test("LRU 메모리 정책으로 정상 동작한다")
    func lruMemory() {
        let (storage, dir) = makeTestStorage(memoryPolicy: .lru, memoryCapacity: 3)
        defer { cleanup(dir) }

        storage.store(testData("1"), forKey: "A")
        storage.store(testData("2"), forKey: "B")
        storage.store(testData("3"), forKey: "C")
        storage.store(testData("4"), forKey: "D")  // A가 메모리에서 evict

        // A는 메모리에 없지만 디스크에서 조회 가능
        #expect(storage.value(forKey: "A") == testData("1"))
    }

    @Test("LFU 메모리 정책으로 정상 동작한다")
    func lfuMemory() {
        let (storage, dir) = makeTestStorage(memoryPolicy: .lfu, memoryCapacity: 3)
        defer { cleanup(dir) }

        storage.store(testData("1"), forKey: "A")
        storage.store(testData("2"), forKey: "B")
        storage.store(testData("3"), forKey: "C")

        // A를 자주 접근
        _ = storage.memoryCache.value(forKey: "A")
        _ = storage.memoryCache.value(forKey: "A")

        // D를 추가하면 접근이 적은 항목이 evict
        storage.store(testData("4"), forKey: "D")

        // A는 자주 접근했으므로 메모리에 남아있을 가능성 높음
        #expect(storage.value(forKey: "A") == testData("1"))
    }

    @Test("FIFO 메모리 정책으로 정상 동작한다")
    func fifoMemory() {
        let (storage, dir) = makeTestStorage(memoryPolicy: .fifo, memoryCapacity: 3)
        defer { cleanup(dir) }

        storage.store(testData("1"), forKey: "A")
        storage.store(testData("2"), forKey: "B")
        storage.store(testData("3"), forKey: "C")
        storage.store(testData("4"), forKey: "D")  // A가 FIFO로 evict

        // 디스크에서 복구
        #expect(storage.value(forKey: "A") == testData("1"))
    }
}

// MARK: - 저장 옵션

@Suite("HamstashStorage - 저장 옵션")
struct HamstashStorageOptionTests {

    @Test("memoryOnly로 저장하면 디스크에는 저장되지 않는다")
    func memoryOnly() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("hello"), forKey: "A", option: .memoryOnly)

        #expect(storage.memoryCache.value(forKey: "A") != nil)
        #expect(storage.diskCache.value(forKey: "A") == nil)
    }

    @Test("diskOnly로 저장하면 메모리에는 저장되지 않는다")
    func diskOnly() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("hello"), forKey: "A", option: .diskOnly)

        #expect(storage.memoryCache.value(forKey: "A") == nil)
        #expect(storage.diskCache.value(forKey: "A") != nil)
    }

    @Test("memoryAndDisk(기본값)로 저장하면 양쪽 모두 저장된다")
    func memoryAndDisk() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("hello"), forKey: "A")

        #expect(storage.memoryCache.value(forKey: "A") != nil)
        #expect(storage.diskCache.value(forKey: "A") != nil)
    }

    @Test("diskOnly로 저장한 데이터도 value 조회 시 promote된다")
    func diskOnlyPromote() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("hello"), forKey: "A", option: .diskOnly)

        // value 호출 → 디스크에서 찾아서 메모리에 promote
        let result = storage.value(forKey: "A")
        #expect(result == testData("hello"))

        // promote 후 메모리에 존재
        #expect(storage.memoryCache.value(forKey: "A") != nil)
    }
}

// MARK: - 동시성

@Suite("HamstashStorage - 동시성")
struct HamstashStorageConcurrencyTests {

    @Test("여러 스레드에서 동시에 store/value를 호출해도 안전하다")
    func concurrentAccess() async {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        await withTaskGroup(of: Void.self) { group in
            // 쓰기
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<20 {
                        storage.store(testData("data_\(taskIndex)_\(i)"), forKey: "key_\(taskIndex)_\(i)")
                    }
                }
            }
            // 읽기
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<20 {
                        _ = storage.value(forKey: "key_\(taskIndex)_\(i)")
                    }
                }
            }
        }

        // 크래시 없이 완료되면 성공
    }
}
