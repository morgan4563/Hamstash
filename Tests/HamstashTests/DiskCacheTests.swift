// DiskCacheTests.swift

import Testing
import Foundation
@testable import Hamstash

// MARK: - 테스트용 헬퍼

/// 각 테스트에서 격리된 DiskCache를 생성한다.
/// 고유한 디렉토리를 사용하여 테스트 간 간섭을 방지한다.
private func makeTestDiskCache(
    totalCostLimit: DiskCache.ByteSize = .unlimited,
    maxAge: TimeInterval = 0
) -> (DiskCache, URL) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let config = DiskCache.Configuration(
        name: "test",
        totalCostLimit: totalCostLimit,
        maxAge: maxAge
    )
    let cache = DiskCache(config: config, directory: tempDir)
    return (cache, tempDir)
}

/// 테스트 종료 후 임시 디렉토리를 정리한다.
private func cleanup(_ directory: URL) {
    try? FileManager.default.removeItem(at: directory)
}

/// 테스트용 데이터를 생성한다.
private func testData(_ string: String = "test") -> Data {
    Data(string.utf8)
}

/// 지정된 바이트 크기의 데이터를 생성한다.
private func testData(size: Int) -> Data {
    Data(count: size)
}

// MARK: - 기본 동작

@Suite("DiskCache - 기본 동작")
struct DiskCacheBasicTests {

    @Test("저장 후 조회하면 데이터가 반환된다")
    func storeAndRetrieve() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        let data = testData("hello")
        cache.store(data, forKey: "A")

        #expect(cache.value(forKey: "A") == data)
    }

    @Test("존재하지 않는 키를 조회하면 nil이 반환된다")
    func missingKey() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        #expect(cache.value(forKey: "nonexistent") == nil)
    }

    @Test("같은 키에 다시 store하면 데이터가 갱신된다")
    func overwrite() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.store(testData("old"), forKey: "A")
        cache.store(testData("new"), forKey: "A")

        #expect(cache.value(forKey: "A") == testData("new"))
    }

    @Test("remove로 특정 키를 제거할 수 있다")
    func removeKey() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "A")
        cache.remove(forKey: "A")

        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("removeAll 후 모든 데이터가 삭제된다")
    func removeAll() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.store(testData("1"), forKey: "A")
        cache.store(testData("2"), forKey: "B")
        cache.store(testData("3"), forKey: "C")

        cache.removeAll()

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == nil)
        #expect(cache.value(forKey: "C") == nil)
    }

    @Test("isCached가 올바르게 동작한다")
    func isCached() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        #expect(cache.isCached(forKey: "A") == false)

        cache.store(testData(), forKey: "A")
        #expect(cache.isCached(forKey: "A") == true)

        cache.remove(forKey: "A")
        #expect(cache.isCached(forKey: "A") == false)
    }

    @Test("totalSize가 실제 파일 크기를 반영한다")
    func totalSize() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        #expect(cache.totalSize == 0)

        let data = testData(size: 1024)
        cache.store(data, forKey: "A")

        #expect(cache.totalSize == 1024)
    }
}

// MARK: - TTL 만료

@Suite("DiskCache - TTL 만료")
struct DiskCacheTTLTests {

    @Test("maxAge 초과 항목은 조회 시 nil이 반환된다")
    func expiredItem() async throws {
        let (cache, dir) = makeTestDiskCache(maxAge: 1)
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "A")

        // 만료 대기
        try await Task.sleep(for: .seconds(1.5))

        #expect(cache.value(forKey: "A") == nil)
    }

    @Test("maxAge 이내 항목은 정상 조회된다")
    func notExpiredYet() {
        let (cache, dir) = makeTestDiskCache(maxAge: 60)
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "A")

        #expect(cache.value(forKey: "A") != nil)
    }

    @Test("maxAge=0이면 만료되지 않는다")
    func noExpiration() {
        let (cache, dir) = makeTestDiskCache(maxAge: 0)
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "A")

        #expect(cache.value(forKey: "A") != nil)
    }

    @Test("만료된 항목은 isCached에서 false를 반환한다")
    func expiredIsCached() async throws {
        let (cache, dir) = makeTestDiskCache(maxAge: 1)
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "A")
        #expect(cache.isCached(forKey: "A") == true)

        try await Task.sleep(for: .seconds(1.5))

        #expect(cache.isCached(forKey: "A") == false)
    }

    @Test("removeExpiredFiles가 만료된 파일을 일괄 정리한다")
    func removeExpiredFiles() async throws {
        let (cache, dir) = makeTestDiskCache(maxAge: 1)
        defer { cleanup(dir) }

        cache.store(testData(size: 100), forKey: "A")
        cache.store(testData(size: 100), forKey: "B")

        try await Task.sleep(for: .seconds(1.5))

        // 만료 후 수동 정리
        cache.removeExpiredFiles()

        #expect(cache.totalSize == 0)
    }
}

// MARK: - 용량 관리

@Suite("DiskCache - 용량 관리")
struct DiskCacheCapacityTests {

    @Test("totalCostLimit 초과 시 오래된 파일이 제거된다")
    func trimOnOverflow() {
        // 500바이트 제한
        let (cache, dir) = makeTestDiskCache(totalCostLimit: .init(bytes: 500))
        defer { cleanup(dir) }

        // 200바이트씩 3개 = 600바이트 → 제한 초과
        cache.store(testData(size: 200), forKey: "A")
        cache.store(testData(size: 200), forKey: "B")
        cache.store(testData(size: 200), forKey: "C")

        // 용량 제한(500)의 75% = 375 이하까지 정리
        // C(200)만 남거나 B+C가 남을 수 있음 (파일 시스템 타이밍에 따라)
        #expect(cache.totalSize <= 500)
    }

    @Test("totalCostLimit=0이면 용량 제한 없이 저장된다")
    func noLimit() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        for i in 0..<100 {
            cache.store(testData(size: 1024), forKey: "key_\(i)")
        }

        #expect(cache.totalSize == 100 * 1024)
    }
}

// MARK: - Edge Case

@Suite("DiskCache - Edge Case")
struct DiskCacheEdgeCaseTests {

    @Test("빈 Data를 저장할 수 있다")
    func emptyData() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        let emptyData = Data()
        cache.store(emptyData, forKey: "empty")

        #expect(cache.value(forKey: "empty") == emptyData)
    }

    @Test("URL 문자열 키가 안전하게 처리된다")
    func urlKey() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        let key = "https://example.com/image.png?size=large&quality=high"
        cache.store(testData(), forKey: key)

        #expect(cache.value(forKey: key) != nil)
    }

    @Test("한글 키가 안전하게 처리된다")
    func koreanKey() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.store(testData(), forKey: "프로필_이미지_123")

        #expect(cache.value(forKey: "프로필_이미지_123") != nil)
    }

    @Test("매우 긴 키(1000자 이상)도 처리된다")
    func longKey() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        let longKey = String(repeating: "x", count: 2000)
        cache.store(testData(), forKey: longKey)

        #expect(cache.value(forKey: longKey) != nil)
    }

    @Test("빈 캐시에서 remove를 호출해도 크래시하지 않는다")
    func removeFromEmpty() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.remove(forKey: "nonexistent")
        // 크래시하지 않으면 성공
    }

    @Test("removeAll 후 다시 store할 수 있다")
    func storeAfterRemoveAll() {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        cache.store(testData("1"), forKey: "A")
        cache.removeAll()
        cache.store(testData("2"), forKey: "B")

        #expect(cache.value(forKey: "A") == nil)
        #expect(cache.value(forKey: "B") == testData("2"))
    }
}

// MARK: - 동시성

@Suite("DiskCache - 동시성")
struct DiskCacheConcurrencyTests {

    @Test("여러 스레드에서 동시에 store해도 크래시하지 않는다")
    func concurrentStore() async {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        await withTaskGroup(of: Void.self) { group in
            for taskIndex in 0..<10 {
                group.addTask {
                    for i in 0..<20 {
                        let key = "task\(taskIndex)_item\(i)"
                        cache.store(testData(key), forKey: key)
                    }
                }
            }
        }

        // 크래시 없이 완료되면 성공
        #expect(cache.totalSize > 0)
    }

    @Test("여러 스레드에서 동시에 store + value해도 크래시하지 않는다")
    func concurrentStoreAndRetrieve() async {
        let (cache, dir) = makeTestDiskCache()
        defer { cleanup(dir) }

        await withTaskGroup(of: Void.self) { group in
            // 쓰기
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<20 {
                        cache.store(testData("data"), forKey: "key_\(taskIndex)_\(i)")
                    }
                }
            }
            // 읽기
            for taskIndex in 0..<5 {
                group.addTask {
                    for i in 0..<20 {
                        _ = cache.value(forKey: "key_\(taskIndex)_\(i)")
                    }
                }
            }
        }
    }
}
