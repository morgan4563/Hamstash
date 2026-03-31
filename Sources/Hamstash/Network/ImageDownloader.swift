// ImageDownloader.swift
// URLSession 기반 이미지 다운로더

import Foundation

/// 이미지 다운로드 중 발생할 수 있는 에러
public enum DownloadError: Error, Sendable {
    /// HTTP 상태 코드가 200번대가 아닌 경우
    case invalidResponse(statusCode: Int)
    /// 응답 데이터가 비어있는 경우
    case emptyData
    /// URL이 유효하지 않은 경우
    case invalidURL
    /// 데이터를 이미지로 변환할 수 없는 경우
    case invalidImageData
}

/// URLSession 기반 이미지 다운로더
///
/// URL 또는 URLRequest로 이미지를 다운로드한다.
/// 같은 URL에 대한 **중복 요청을 자동으로 병합**하여 네트워크 낭비를 방지한다.
///
/// ```swift
/// // 기본 사용법
/// let data = try await ImageDownloader.default.download(from: url)
///
/// // 헤더가 필요할 때
/// var request = URLRequest(url: url)
/// request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
/// let data = try await ImageDownloader.default.download(request: request)
/// ```
///
/// **중복 요청 병합**:
/// 같은 URL에 대해 동시에 여러 곳에서 요청하면, 실제 네트워크 요청은 1회만 실행되고
/// 모든 호출자가 동일한 결과를 받는다.
public final class ImageDownloader: Sendable {

    // MARK: - 공유 인스턴스

    /// 기본 설정의 공유 인스턴스
    public static let `default` = ImageDownloader()

    // MARK: - 프로퍼티

    private let session: URLSession

    /// 진행 중인 다운로드를 URL별로 관리 (중복 요청 병합용)
    private let activeDownloads = ActiveDownloads()

    // MARK: - 초기화

    /// - Parameter session: 사용할 URLSession (기본: `.shared`)
    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - 다운로드 API

    /// URL로 이미지를 다운로드한다.
    /// - Parameter url: 이미지 URL
    /// - Returns: 다운로드된 이미지 데이터
    /// - Throws: `DownloadError`
    public func download(from url: URL) async throws -> Data {
        try await download(request: URLRequest(url: url))
    }

    /// URLRequest로 이미지를 다운로드한다.
    ///
    /// 커스텀 헤더(Authorization, API Key 등)가 필요할 때 사용한다.
    /// 같은 URL에 대한 중복 요청은 자동으로 병합된다.
    ///
    /// - Parameter request: 이미지 요청
    /// - Returns: 다운로드된 이미지 데이터
    /// - Throws: `DownloadError`
    public func download(request: URLRequest) async throws -> Data {
        guard let url = request.url else {
            throw DownloadError.invalidURL
        }

        let key = url.absoluteString

        // actor 내부에서 원자적으로 기존 Task 조회 또는 새 Task 등록
        let task = await activeDownloads.existingOrNew(forKey: key) {
            Task<Data, Error> {
                defer {
                    Task { await self.activeDownloads.remove(forKey: key) }
                }
                return try await self.performDownload(request: request)
            }
        }

        return try await task.value
    }

    // MARK: - 내부 로직

    /// 실제 네트워크 요청을 수행한다.
    private func performDownload(request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.invalidResponse(statusCode: 0)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw DownloadError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        guard !data.isEmpty else {
            throw DownloadError.emptyData
        }

        return data
    }
}

// MARK: - 중복 요청 관리

/// 진행 중인 다운로드 Task를 URL별로 관리하는 actor
///
/// actor로 구현하여 동시 접근 시에도 안전하게 Task를 등록/조회/제거할 수 있다.
/// `existingOrNew`로 조회와 등록을 원자적으로 처리하여 TOCTOU 레이스를 방지한다.
private actor ActiveDownloads {
    private var tasks: [String: Task<Data, Error>] = [:]

    /// 기존 Task가 있으면 반환, 없으면 새 Task를 등록하고 반환한다.
    ///
    /// actor 내부에서 실행되므로 조회 → 등록이 원자적으로 처리된다.
    func existingOrNew(
        forKey key: String,
        create: () -> Task<Data, Error>
    ) -> Task<Data, Error> {
        if let existing = tasks[key] {
            return existing
        }
        let newTask = create()
        tasks[key] = newTask
        return newTask
    }

    func remove(forKey key: String) {
        tasks.removeValue(forKey: key)
    }
}
