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

// MARK: - 캐시 통계

@Suite("HamstashStorage - 캐시 통계")
struct HamstashStorageStatisticsTests {

    @Test("메모리 히트가 정확하게 카운트된다")
    func memoryHit() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("A"), forKey: "A")
        _ = storage.value(forKey: "A")
        _ = storage.value(forKey: "A")

        let stats = storage.statistics
        #expect(stats.memoryHitCount == 2)
        #expect(stats.diskHitCount == 0)
        #expect(stats.missCount == 0)
    }

    @Test("디스크 히트가 정확하게 카운트된다")
    func diskHit() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("A"), forKey: "A")
        storage.clearMemory()

        _ = storage.value(forKey: "A")

        let stats = storage.statistics
        #expect(stats.memoryHitCount == 0)
        #expect(stats.diskHitCount == 1)
    }

    @Test("미스가 정확하게 카운트된다")
    func miss() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        _ = storage.value(forKey: "없는키")
        _ = storage.value(forKey: "없는키2")

        let stats = storage.statistics
        #expect(stats.missCount == 2)
        #expect(stats.hitCount == 0)
    }

    @Test("hitRate가 정확하게 계산된다")
    func hitRate() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("A"), forKey: "A")
        _ = storage.value(forKey: "A")       // 메모리 히트
        _ = storage.value(forKey: "없는키")   // 미스

        let stats = storage.statistics
        #expect(stats.hitRate == 0.5)
        #expect(stats.totalCount == 2)
    }

    @Test("조회 기록이 없으면 hitRate는 0이다")
    func emptyHitRate() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        #expect(storage.statistics.hitRate == 0)
        #expect(storage.statistics.totalCount == 0)
    }

    @Test("resetStatistics가 카운터를 초기화한다")
    func reset() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.store(testData("A"), forKey: "A")
        _ = storage.value(forKey: "A")
        _ = storage.value(forKey: "없는키")

        storage.resetStatistics()

        let stats = storage.statistics
        #expect(stats.memoryHitCount == 0)
        #expect(stats.diskHitCount == 0)
        #expect(stats.missCount == 0)
    }
}

// MARK: - Named Cache

@Suite("HamstashStorage - Named Cache")
struct HamstashStorageNamedTests {

    @Test("같은 이름이면 같은 인스턴스를 반환한다")
    func sameNameSameInstance() {
        defer { HamstashStorage.removeAllNamed() }

        let a = HamstashStorage.named("test_same")
        let b = HamstashStorage.named("test_same")

        #expect(a === b)
    }

    @Test("다른 이름이면 다른 인스턴스를 반환한다")
    func differentNameDifferentInstance() {
        defer { HamstashStorage.removeAllNamed() }

        let a = HamstashStorage.named("test_alpha")
        let b = HamstashStorage.named("test_beta")

        #expect(a !== b)
    }

    @Test("Named Cache 간 데이터가 격리된다")
    func dataIsolation() {
        defer { HamstashStorage.removeAllNamed() }

        let profile = HamstashStorage.named("test_profile")
        let thumbnail = HamstashStorage.named("test_thumbnail")

        profile.store(testData("프로필"), forKey: "user1")
        thumbnail.store(testData("썸네일"), forKey: "user1")

        #expect(profile.value(forKey: "user1") == testData("프로필"))
        #expect(thumbnail.value(forKey: "user1") == testData("썸네일"))
    }

    @Test("removeNamed가 레지스트리에서 제거한다")
    func removeNamed() {
        let a = HamstashStorage.named("test_remove")
        HamstashStorage.removeNamed("test_remove")
        let b = HamstashStorage.named("test_remove")

        // 제거 후 새로 만들면 다른 인스턴스
        #expect(a !== b)

        HamstashStorage.removeAllNamed()
    }
}

// MARK: - Pin (고정 항목)

@Suite("HamstashStorage - Pin")
struct HamstashStoragePinTests {

    @Test("고정된 항목이 조회된다")
    func pinAndRetrieve() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        let data = testData("logo")
        storage.pin(data, forKey: "logo")

        #expect(storage.value(forKey: "logo") == data)
    }

    @Test("고정된 항목은 메모리 캐시를 비워도 유지된다")
    func pinSurvivesClearMemory() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.clearMemory()

        #expect(storage.value(forKey: "logo") == testData("logo"))
    }

    @Test("고정된 항목은 캐시 정책에 의해 제거되지 않는다")
    func pinSurvivesEviction() {
        let (storage, dir) = makeTestStorage(memoryCapacity: 2)
        defer { cleanup(dir) }

        // logo를 고정
        storage.pin(testData("logo"), forKey: "logo")

        // 캐시를 가득 채우고 넘침 → 일반 항목은 evict
        storage.store(testData("1"), forKey: "A")
        storage.store(testData("2"), forKey: "B")
        storage.store(testData("3"), forKey: "C")

        // 고정 항목은 캐시 정책과 별개이므로 항상 존재
        #expect(storage.value(forKey: "logo") == testData("logo"))
    }

    @Test("unpin 후 keepInCache=true면 일반 캐시로 이동한다")
    func unpinKeepInCache() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.unpin(forKey: "logo", keepInCache: true)

        #expect(storage.isPinned(forKey: "logo") == false)
        // 일반 메모리 캐시로 이동했으므로 조회 가능
        #expect(storage.memoryCache.value(forKey: "logo") == testData("logo"))
    }

    @Test("unpin 후 keepInCache=false면 메모리에서 제거된다")
    func unpinRemoveFromMemory() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.unpin(forKey: "logo", keepInCache: false)

        #expect(storage.isPinned(forKey: "logo") == false)
        #expect(storage.memoryCache.value(forKey: "logo") == nil)
        // 디스크에는 남아있음
        #expect(storage.diskCache.value(forKey: "logo") == testData("logo"))
    }

    @Test("isPinned가 정확하게 반환한다")
    func isPinned() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        #expect(storage.isPinned(forKey: "logo") == false)

        storage.pin(testData("logo"), forKey: "logo")
        #expect(storage.isPinned(forKey: "logo") == true)

        storage.unpin(forKey: "logo")
        #expect(storage.isPinned(forKey: "logo") == false)
    }

    @Test("remove는 고정 항목도 제거한다")
    func removeAlsoUnpins() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.remove(forKey: "logo")

        #expect(storage.isPinned(forKey: "logo") == false)
        #expect(storage.value(forKey: "logo") == nil)
    }

    @Test("clearAll은 고정 항목도 모두 제거한다")
    func clearAllRemovesPins() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.pin(testData("icon"), forKey: "icon")
        storage.clearAll()

        #expect(storage.pinnedCount == 0)
        #expect(storage.value(forKey: "logo") == nil)
    }

    @Test("pinnedCount가 정확하다")
    func pinnedCount() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        #expect(storage.pinnedCount == 0)

        storage.pin(testData("a"), forKey: "A")
        storage.pin(testData("b"), forKey: "B")
        #expect(storage.pinnedCount == 2)

        storage.unpin(forKey: "A")
        #expect(storage.pinnedCount == 1)
    }

    @Test("고정 항목 조회도 통계에 반영된다")
    func pinHitCountsAsMemoryHit() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        _ = storage.value(forKey: "logo")

        #expect(storage.statistics.memoryHitCount == 1)
    }

    @Test("isCached가 고정 항목도 감지한다")
    func isCachedDetectsPin() {
        let (storage, dir) = makeTestStorage()
        defer { cleanup(dir) }

        storage.pin(testData("logo"), forKey: "logo")
        storage.clearMemory()
        storage.clearDisk()

        // 메모리/디스크 비워도 pin은 감지됨
        // (pin할 때 디스크에도 저장되므로 clearDisk 후에는 디스크에 없지만 pin 자체는 남아있음)
        #expect(storage.isCached(forKey: "logo") == true)
    }
}
