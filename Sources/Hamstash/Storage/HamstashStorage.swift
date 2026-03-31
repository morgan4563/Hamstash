// HamstashStorage.swift
// 메모리 + 디스크 2단계 캐시

import Foundation

/// 메모리 + 디스크 2단계 캐시
///
/// 조회 순서: **메모리 캐시 → 디스크 캐시 → nil**
/// 저장 시: 메모리 캐시 + 디스크 캐시 양쪽에 저장
///
/// 디스크에서 찾은 데이터는 메모리에 다시 올려놓는다 (promote).
/// 이후 같은 키를 조회하면 메모리에서 바로 반환된다.
///
/// ```swift
/// let storage = HamstashStorage(
///     memoryPolicy: .lru,
///     memoryCapacity: 100,
///     diskConfig: .init(name: "images", totalCostLimit: 50 * 1024 * 1024)
/// )
/// storage.store(imageData, forKey: "profile_123")
/// let data = storage.value(forKey: "profile_123")
/// ```
public final class HamstashStorage: @unchecked Sendable {

    // MARK: - 프로퍼티

    /// 메모리 캐시 (1단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let memoryCache: ImageCache

    /// 디스크 캐시 (2단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let diskCache: DiskCache

    // MARK: - 초기화

    /// - Parameters:
    ///   - memoryPolicy: 메모리 캐시 교체 정책 (기본: .lru)
    ///   - memoryCapacity: 메모리 캐시 최대 항목 수 (기본: 100)
    ///   - diskConfig: 디스크 캐시 설정
    public init(
        memoryPolicy: HamstashCache<String, Data>.Policy = .lru,
        memoryCapacity: Int = 100,
        diskConfig: DiskCache.Configuration = .init()
    ) {
        self.memoryCache = ImageCache(policy: memoryPolicy, capacity: memoryCapacity)
        self.diskCache = DiskCache(config: diskConfig)
    }

    /// 테스트용 — 디스크 캐시를 직접 주입할 수 있는 초기화
    init(memoryCache: ImageCache, diskCache: DiskCache) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
    }

    // MARK: - 공개 API

    /// 메모리 + 디스크에 데이터를 저장한다.
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 식별 키
    public func store(_ data: Data, forKey key: String) {
        memoryCache.store(data, forKey: key)
        diskCache.store(data, forKey: key)
    }

    /// 2단계 탐색으로 데이터를 조회한다.
    ///
    /// 1. 메모리에 있으면 즉시 반환
    /// 2. 없으면 디스크에서 조회
    /// 3. 디스크에서 찾으면 메모리에 다시 올려놓는다 (promote)
    ///
    /// - Parameter key: 조회할 키
    /// - Returns: 데이터 또는 nil
    public func value(forKey key: String) -> Data? {
        // 1단계: 메모리 캐시
        if let memoryData = memoryCache.value(forKey: key) {
            return memoryData
        }

        // 2단계: 디스크 캐시
        guard let diskData = diskCache.value(forKey: key) else {
            return nil
        }

        // 디스크 히트 → 메모리에 promote
        memoryCache.store(diskData, forKey: key)
        return diskData
    }

    /// 메모리 + 디스크 양쪽에서 제거한다.
    /// - Parameter key: 제거할 키
    public func remove(forKey key: String) {
        memoryCache.remove(forKey: key)
        diskCache.remove(forKey: key)
    }

    /// 메모리 캐시만 비운다.
    ///
    /// 메모리 부족 경고(`didReceiveMemoryWarning`) 등에서 사용.
    /// 디스크 캐시에는 데이터가 남아있으므로 다시 조회하면 promote된다.
    public func clearMemory() {
        memoryCache.removeAll()
    }

    /// 디스크 캐시만 비운다.
    public func clearDisk() {
        diskCache.removeAll()
    }

    /// 메모리 + 디스크 모두 비운다.
    public func clearAll() {
        memoryCache.removeAll()
        diskCache.removeAll()
    }

    /// 특정 키가 캐시에 존재하는지 확인한다.
    /// - Parameter key: 확인할 키
    /// - Returns: 메모리 또는 디스크에 존재 여부
    public func isCached(forKey key: String) -> Bool {
        if memoryCache.value(forKey: key) != nil {
            return true
        }
        return diskCache.isCached(forKey: key)
    }

    /// 디스크에서 만료된 파일들을 일괄 정리한다.
    ///
    /// 앱 진입 시점이나 백그라운드 전환 시 호출하면 디스크 공간을 확보할 수 있다.
    public func removeExpiredDiskFiles() {
        diskCache.removeExpiredFiles()
    }

    /// 현재 디스크 사용량 (바이트)
    public var diskSize: Int {
        diskCache.totalSize
    }
}
