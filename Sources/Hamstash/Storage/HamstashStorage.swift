// HamstashStorage.swift
// 메모리 + 디스크 2단계 캐시

import Foundation
#if canImport(UIKit)
import UIKit
#endif

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
/// // 커스텀 설정
/// let storage = HamstashStorage(
///     memoryPolicy: .lru,
///     memoryCapacity: 200,
///     diskConfig: .init(name: "images", totalCostLimit: .megabytes(50))
/// )
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

    // MARK: - 프로퍼티

    /// 메모리 캐시 (1단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let memoryCache: ImageCache

    /// 디스크 캐시 (2단계). 개별 계층에 직접 접근이 필요할 때 사용.
    public let diskCache: DiskCache

    /// 이미지 다운로더. 개별 접근이 필요할 때 사용.
    public let downloader: ImageDownloader

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
    /// 메모리 부족 경고 시 자동으로 호출된다.
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
    /// 조회 순서: **메모리 → 디스크 → 네트워크 다운로드**
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

        // 1단계: 캐시 확인 (메모리 → 디스크)
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
