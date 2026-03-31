// HamstashStorage.swift
// 메모리 + 디스크 2단계 캐시

import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 캐시 히트/미스 통계
///
/// ```swift
/// let stats = storage.statistics
/// print("히트율: \(stats.hitRate * 100)%")
/// print("메모리 히트: \(stats.memoryHitCount), 디스크 히트: \(stats.diskHitCount)")
/// ```
public struct CacheStatistics: Sendable, Equatable {
    /// 메모리 캐시에서 바로 찾은 횟수
    public let memoryHitCount: Int
    /// 디스크 캐시에서 찾은 횟수
    public let diskHitCount: Int
    /// 캐시에 없어서 못 찾은 횟수
    public let missCount: Int

    /// 전체 히트 횟수 (메모리 + 디스크)
    public var hitCount: Int { memoryHitCount + diskHitCount }
    /// 전체 조회 횟수
    public var totalCount: Int { hitCount + missCount }
    /// 히트율 (0.0 ~ 1.0). 조회 기록이 없으면 0.
    public var hitRate: Double {
        guard totalCount > 0 else { return 0 }
        return Double(hitCount) / Double(totalCount)
    }
}

/// 메모리 + 디스크 2단계 캐시
///
/// 조회 순서: **메모리 캐시 → 디스크 캐시 → nil**
/// 저장 시: 메모리 캐시 + 디스크 캐시 양쪽에 저장 (옵션으로 변경 가능)
///
/// 디스크에서 찾은 데이터는 메모리에 다시 올려놓는다 (promote).
/// 이후 같은 키를 조회하면 메모리에서 바로 반환된다.
///
/// ```swift
/// // 간단한 사용법 (기본 설정)
/// HamstashStorage.default.store(imageData, forKey: "profile_123")
/// let data = HamstashStorage.default.value(forKey: "profile_123")
///
/// // 용도별 캐시 분리
/// let profileStorage = HamstashStorage.named("profile")
/// let thumbnailStorage = HamstashStorage.named("thumbnail")
///
/// // 중요 이미지 고정 (캐시 정책에 의해 제거되지 않음)
/// storage.pin(imageData, forKey: "logo")
///
/// // 캐시 통계 확인
/// let stats = storage.statistics
/// print("히트율: \(stats.hitRate * 100)%")
/// ```
///
/// **자동 관리** (iOS):
/// - 메모리 부족 경고 시 메모리 캐시 자동 비움
/// - 앱이 백그라운드로 전환 시 만료된 디스크 파일 자동 정리
public final class HamstashStorage: @unchecked Sendable {

    // MARK: - 저장 옵션

    /// 데이터를 저장할 위치를 지정한다.
    public enum StorageOption: Sendable {
        /// 메모리 + 디스크 양쪽에 저장 (기본값)
        case memoryAndDisk
        /// 메모리에만 저장 (앱 종료 시 사라짐)
        case memoryOnly
        /// 디스크에만 저장 (메모리 절약이 필요할 때)
        case diskOnly
    }

    // MARK: - 공유 인스턴스

    /// 기본 설정의 공유 인스턴스
    ///
    /// - 메모리: LRU, 100개 항목
    /// - 디스크: 150MB, 7일 만료
    ///
    /// 대부분의 이미지 캐싱 시나리오에 적합한 기본 설정.
    /// 커스텀이 필요하면 `init()`으로 직접 생성.
    public static let `default` = HamstashStorage(
        memoryPolicy: .lru,
        memoryCapacity: 100,
        diskConfig: .init(
            name: "default",
            totalCostLimit: .megabytes(150),
            maxAge: 7 * 24 * 60 * 60  // 7일
        )
    )

    // MARK: - Named Cache 레지스트리

    private static let registryLock = NSLock()
    // NSLock으로 보호되는 공유 상태
    nonisolated(unsafe) private static var registry: [String: HamstashStorage] = [:]

    /// 이름으로 캐시를 가져온다. 같은 이름이면 같은 인스턴스를 반환한다.
    ///
    /// 용도별로 캐시를 분리할 때 사용한다. 디스크 저장 경로도 이름별로 분리된다.
    ///
    /// ```swift
    /// let profileCache = HamstashStorage.named("profile")
    /// let thumbnailCache = HamstashStorage.named("thumbnail", memoryCapacity: 200)
    /// ```
    ///
    /// - Parameters:
    ///   - name: 캐시 이름 (디스크 디렉토리명으로도 사용)
    ///   - memoryPolicy: 메모리 캐시 교체 정책 (기본: .lru)
    ///   - memoryCapacity: 메모리 캐시 최대 항목 수 (기본: 100)
    ///   - diskTotalCostLimit: 디스크 최대 용량 (기본: 150MB)
    ///   - diskMaxAge: 디스크 항목 최대 수명 초 (기본: 7일)
    /// - Returns: 해당 이름의 캐시 인스턴스
    public static func named(
        _ name: String,
        memoryPolicy: HamstashCache<String, Data>.Policy = .lru,
        memoryCapacity: Int = 100,
        diskTotalCostLimit: DiskCache.ByteSize = .megabytes(150),
        diskMaxAge: TimeInterval = 7 * 24 * 60 * 60
    ) -> HamstashStorage {
        registryLock.lock()
        defer { registryLock.unlock() }

        if let existing = registry[name] {
            return existing
        }

        let storage = HamstashStorage(
            memoryPolicy: memoryPolicy,
            memoryCapacity: memoryCapacity,
            diskConfig: .init(
                name: name,
                totalCostLimit: diskTotalCostLimit,
                maxAge: diskMaxAge
            )
        )
        registry[name] = storage
        return storage
    }

    /// Named Cache 레지스트리에서 특정 이름의 캐시를 제거한다.
    /// - Parameter name: 제거할 캐시 이름
    public static func removeNamed(_ name: String) {
        registryLock.lock()
        defer { registryLock.unlock() }
        registry.removeValue(forKey: name)
    }

    /// Named Cache 레지스트리를 모두 비운다.
    public static func removeAllNamed() {
        registryLock.lock()
        defer { registryLock.unlock() }
        registry.removeAll()
    }

    // MARK: - 프로퍼티

    /// 메모리 캐시 (1단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let memoryCache: ImageCache

    /// 디스크 캐시 (2단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let diskCache: DiskCache

    /// 이미지 다운로더. 개별 접근이 필요할 때 사용.
    public let downloader: ImageDownloader

    // MARK: - 통계 + Pin 내부 상태

    private let stateLock = NSLock()
    private var _memoryHitCount: Int = 0
    private var _diskHitCount: Int = 0
    private var _missCount: Int = 0
    private var _pinnedItems: [String: Data] = [:]

    // MARK: - 초기화

    /// - Parameters:
    ///   - memoryPolicy: 메모리 캐시 교체 정책 (기본: .lru)
    ///   - memoryCapacity: 메모리 캐시 최대 항목 수 (기본: 100)
    ///   - diskConfig: 디스크 캐시 설정
    ///   - downloader: 이미지 다운로더 (기본: `.default`)
    public init(
        memoryPolicy: HamstashCache<String, Data>.Policy = .lru,
        memoryCapacity: Int = 100,
        diskConfig: DiskCache.Configuration = .init(),
        downloader: ImageDownloader = .default
    ) {
        self.memoryCache = ImageCache(policy: memoryPolicy, capacity: memoryCapacity)
        self.diskCache = DiskCache(config: diskConfig)
        self.downloader = downloader
        registerLifecycleObservers()
    }

    /// 테스트용 — 의존성을 직접 주입할 수 있는 초기화
    init(memoryCache: ImageCache, diskCache: DiskCache, downloader: ImageDownloader = .default) {
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.downloader = downloader
    }

    deinit {
        #if canImport(UIKit) && !os(watchOS)
        NotificationCenter.default.removeObserver(self)
        #endif
    }

    // MARK: - 캐시 통계

    /// 현재 캐시 히트/미스 통계를 반환한다.
    public var statistics: CacheStatistics {
        stateLock.lock()
        defer { stateLock.unlock() }
        return CacheStatistics(
            memoryHitCount: _memoryHitCount,
            diskHitCount: _diskHitCount,
            missCount: _missCount
        )
    }

    /// 통계 카운터를 초기화한다.
    public func resetStatistics() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _memoryHitCount = 0
        _diskHitCount = 0
        _missCount = 0
    }

    private func recordMemoryHit() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _memoryHitCount += 1
    }

    private func recordDiskHit() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _diskHitCount += 1
    }

    private func recordMiss() {
        stateLock.lock()
        defer { stateLock.unlock() }
        _missCount += 1
    }

    // MARK: - Pin (고정 항목)

    /// 데이터를 고정한다. 고정된 항목은 캐시 정책(LRU 등)에 의해 제거되지 않는다.
    ///
    /// 앱 로고, 자주 쓰는 아이콘 등 항상 메모리에 유지해야 하는 이미지에 사용한다.
    /// 디스크에도 함께 저장된다.
    ///
    /// ```swift
    /// storage.pin(logoData, forKey: "app_logo")
    /// ```
    ///
    /// - Parameters:
    ///   - data: 고정할 데이터
    ///   - key: 식별 키
    public func pin(_ data: Data, forKey key: String) {
        stateLock.lock()
        _pinnedItems[key] = data
        stateLock.unlock()

        diskCache.store(data, forKey: key)
    }

    /// 고정을 해제한다. 해제된 항목은 일반 캐시 정책의 대상이 된다.
    ///
    /// `keepInCache`가 true(기본)이면 일반 캐시로 이동하고,
    /// false이면 메모리에서 완전히 제거한다. 디스크에는 남아있다.
    ///
    /// - Parameters:
    ///   - key: 해제할 키
    ///   - keepInCache: 해제 후 일반 캐시로 이동할지 여부 (기본: true)
    public func unpin(forKey key: String, keepInCache: Bool = true) {
        stateLock.lock()
        let data = _pinnedItems.removeValue(forKey: key)
        stateLock.unlock()

        if keepInCache, let data {
            memoryCache.store(data, forKey: key)
        }
    }

    /// 해당 키가 고정되어 있는지 확인한다.
    /// - Parameter key: 확인할 키
    /// - Returns: 고정 여부
    public func isPinned(forKey key: String) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _pinnedItems[key] != nil
    }

    /// 모든 고정 항목을 해제한다.
    public func unpinAll() {
        stateLock.lock()
        _pinnedItems.removeAll()
        stateLock.unlock()
    }

    /// 현재 고정된 항목 수
    public var pinnedCount: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return _pinnedItems.count
    }

    // MARK: - 공개 API

    /// 메모리 + 디스크에 데이터를 저장한다.
    /// - Parameters:
    ///   - data: 저장할 데이터
    ///   - key: 식별 키
    ///   - option: 저장 위치 (기본: `.memoryAndDisk`)
    public func store(_ data: Data, forKey key: String, option: StorageOption = .memoryAndDisk) {
        switch option {
        case .memoryAndDisk:
            memoryCache.store(data, forKey: key)
            diskCache.store(data, forKey: key)
        case .memoryOnly:
            memoryCache.store(data, forKey: key)
        case .diskOnly:
            diskCache.store(data, forKey: key)
        }
    }

    /// 2단계 탐색으로 데이터를 조회한다.
    ///
    /// 조회 순서: **Pin → 메모리 → 디스크**
    /// 디스크에서 찾으면 메모리에 다시 올려놓는다 (promote).
    ///
    /// - Parameter key: 조회할 키
    /// - Returns: 데이터 또는 nil
    public func value(forKey key: String) -> Data? {
        // 0단계: 고정 항목
        stateLock.lock()
        if let pinned = _pinnedItems[key] {
            _memoryHitCount += 1
            stateLock.unlock()
            return pinned
        }
        stateLock.unlock()

        // 1단계: 메모리 캐시
        if let memoryData = memoryCache.value(forKey: key) {
            recordMemoryHit()
            return memoryData
        }

        // 2단계: 디스크 캐시
        guard let diskData = diskCache.value(forKey: key) else {
            recordMiss()
            return nil
        }

        // 디스크 히트 → 메모리에 promote
        recordDiskHit()
        memoryCache.store(diskData, forKey: key)
        return diskData
    }

    /// 메모리 + 디스크 양쪽에서 제거한다. 고정 항목도 함께 해제된다.
    /// - Parameter key: 제거할 키
    public func remove(forKey key: String) {
        stateLock.lock()
        _pinnedItems.removeValue(forKey: key)
        stateLock.unlock()

        memoryCache.remove(forKey: key)
        diskCache.remove(forKey: key)
    }

    /// 메모리 캐시만 비운다. **고정 항목은 유지된다.**
    ///
    /// 메모리 부족 경고 시 자동으로 호출된다.
    /// 디스크 캐시에는 데이터가 남아있으므로 다시 조회하면 promote된다.
    public func clearMemory() {
        memoryCache.removeAll()
    }

    /// 디스크 캐시만 비운다.
    public func clearDisk() {
        diskCache.removeAll()
    }

    /// 메모리 + 디스크 + 고정 항목 모두 비운다.
    public func clearAll() {
        unpinAll()
        memoryCache.removeAll()
        diskCache.removeAll()
    }

    /// 특정 키가 캐시에 존재하는지 확인한다 (고정 항목 포함).
    /// - Parameter key: 확인할 키
    /// - Returns: 메모리, 디스크, 또는 고정 항목에 존재 여부
    public func isCached(forKey key: String) -> Bool {
        if isPinned(forKey: key) {
            return true
        }
        if memoryCache.value(forKey: key) != nil {
            return true
        }
        return diskCache.isCached(forKey: key)
    }

    /// 디스크에서 만료된 파일들을 일괄 정리한다.
    ///
    /// 앱이 백그라운드로 전환될 때 자동으로 호출된다.
    /// 수동으로 호출해도 무방하다.
    public func removeExpiredDiskFiles() {
        diskCache.removeExpiredFiles()
    }

    /// 현재 디스크 사용량 (바이트)
    public var diskSize: Int {
        diskCache.totalSize
    }

    // MARK: - 네트워크 통합 API

    /// URL로 이미지를 가져온다. 캐시에 있으면 캐시에서, 없으면 다운로드 후 캐싱한다.
    ///
    /// 조회 순서: **Pin → 메모리 → 디스크 → 네트워크 다운로드**
    ///
    /// ```swift
    /// let data = try await HamstashStorage.default.image(from: url)
    /// ```
    ///
    /// - Parameter url: 이미지 URL
    /// - Returns: 이미지 데이터
    /// - Throws: `DownloadError`
    public func image(from url: URL) async throws -> Data {
        try await image(request: URLRequest(url: url))
    }

    /// URLRequest로 이미지를 가져온다. 캐시에 있으면 캐시에서, 없으면 다운로드 후 캐싱한다.
    ///
    /// 커스텀 헤더(Authorization 등)가 필요할 때 사용한다.
    ///
    /// ```swift
    /// var request = URLRequest(url: url)
    /// request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
    /// let data = try await storage.image(request: request)
    /// ```
    ///
    /// - Parameter request: 이미지 요청
    /// - Returns: 이미지 데이터
    /// - Throws: `DownloadError`
    public func image(request: URLRequest) async throws -> Data {
        guard let url = request.url else {
            throw DownloadError.invalidURL
        }

        let key = url.absoluteString

        // 1단계: 캐시 확인 (Pin → 메모리 → 디스크)
        if let cached = value(forKey: key) {
            return cached
        }

        // 2단계: 네트워크 다운로드
        let data = try await downloader.download(request: request)

        // 3단계: 캐시에 저장
        store(data, forKey: key)

        return data
    }

    // MARK: - 앱 생명주기 자동 관리

    /// 메모리 경고 및 백그라운드 전환 알림을 구독한다.
    private func registerLifecycleObservers() {
        #if canImport(UIKit) && !os(watchOS)
        // 메모리 부족 경고 → 메모리 캐시 자동 비움
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        // 백그라운드 진입 → 만료된 디스크 파일 자동 정리
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        #endif
    }

    #if canImport(UIKit) && !os(watchOS)
    @objc private func handleMemoryWarning() {
        clearMemory()
    }

    @objc private func handleDidEnterBackground() {
        removeExpiredDiskFiles()
    }
    #endif
}
