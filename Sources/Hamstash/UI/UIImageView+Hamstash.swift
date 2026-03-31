// UIImageView+Hamstash.swift
// UIKit UIImageView 확장 — imageView.hm.setImage(with:)

#if canImport(UIKit)
import UIKit
import ObjectiveC

// MARK: - Hamstash 네임스페이스

/// Hamstash 기능에 접근하기 위한 래퍼
///
/// ```swift
/// // 기본 사용법
/// imageView.hm.setImage(with: url)
///
/// // placeholder + 콜백
/// imageView.hm.setImage(
///     with: url,
///     placeholder: UIImage(named: "placeholder")
/// ) { result in
///     switch result {
///     case .success(let image): print("loaded")
///     case .failure(let error): print("failed: \(error)")
///     }
/// }
///
/// // 헤더가 필요할 때
/// var request = URLRequest(url: url)
/// request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
/// imageView.hm.setImage(request: request)
///
/// // 다운로드 취소 (셀 재사용 시)
/// imageView.hm.cancelDownload()
/// ```
public struct HamstashWrapper: Sendable {

    let base: UIImageView

    init(_ base: UIImageView) {
        self.base = base
    }
}

extension UIImageView {

    /// Hamstash 이미지 로딩 네임스페이스
    public var hm: HamstashWrapper {
        HamstashWrapper(self)
    }
}

// MARK: - Associated Object 키

private enum AssociatedKeys {
    nonisolated(unsafe) static var task: UInt8 = 0
    nonisolated(unsafe) static var url: UInt8 = 0
}

// MARK: - 이미지 로딩 API

extension HamstashWrapper {

    /// URL로 이미지를 로딩한다.
    ///
    /// 이전에 진행 중이던 다운로드가 있으면 자동으로 취소된다.
    /// 캐시에 있으면 캐시에서, 없으면 다운로드 후 표시한다.
    ///
    /// - Parameters:
    ///   - url: 이미지 URL (nil이면 placeholder만 표시)
    ///   - placeholder: 로딩 중 표시할 이미지
    ///   - storage: 사용할 캐시 스토리지 (기본: `.default`)
    ///   - completion: 완료 콜백
    @MainActor
    public func setImage(
        with url: URL?,
        placeholder: UIImage? = nil,
        storage: HamstashStorage = .default,
        completion: (@MainActor @Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        // 이전 요청 취소
        cancelDownload()

        guard let url else {
            base.image = placeholder
            return
        }

        setCurrentURL(url)
        base.image = placeholder

        let task = Task { @MainActor [weak base] in
            do {
                let data = try await storage.image(from: url)
                guard !Task.isCancelled else { return }

                // 셀 재사용으로 URL이 바뀌었으면 무시
                guard currentURL == url else { return }

                guard let uiImage = UIImage(data: data) else {
                    completion?(.failure(DownloadError.invalidImageData))
                    return
                }

                base?.image = uiImage
                completion?(.success(uiImage))
            } catch {
                guard !Task.isCancelled else { return }
                completion?(.failure(error))
            }
        }

        setCurrentTask(task)
    }

    /// URLRequest로 이미지를 로딩한다.
    ///
    /// 커스텀 헤더(Authorization, API Key 등)가 필요할 때 사용한다.
    ///
    /// - Parameters:
    ///   - request: 이미지 요청
    ///   - placeholder: 로딩 중 표시할 이미지
    ///   - storage: 사용할 캐시 스토리지 (기본: `.default`)
    ///   - completion: 완료 콜백
    @MainActor
    public func setImage(
        request: URLRequest,
        placeholder: UIImage? = nil,
        storage: HamstashStorage = .default,
        completion: (@MainActor @Sendable (Result<UIImage, Error>) -> Void)? = nil
    ) {
        cancelDownload()

        guard let url = request.url else {
            base.image = placeholder
            return
        }

        setCurrentURL(url)
        base.image = placeholder

        let task = Task { @MainActor [weak base] in
            do {
                let data = try await storage.image(request: request)
                guard !Task.isCancelled else { return }
                guard currentURL == url else { return }

                guard let uiImage = UIImage(data: data) else {
                    completion?(.failure(DownloadError.invalidImageData))
                    return
                }

                base?.image = uiImage
                completion?(.success(uiImage))
            } catch {
                guard !Task.isCancelled else { return }
                completion?(.failure(error))
            }
        }

        setCurrentTask(task)
    }

    /// 진행 중인 다운로드를 취소한다.
    ///
    /// UITableView/UICollectionView 셀 재사용 시 호출하면
    /// 이전 셀의 이미지가 잘못 표시되는 것을 방지할 수 있다.
    ///
    /// ```swift
    /// override func prepareForReuse() {
    ///     super.prepareForReuse()
    ///     profileImageView.hm.cancelDownload()
    /// }
    /// ```
    public func cancelDownload() {
        currentTask?.cancel()
        setCurrentTask(nil)
    }

    // MARK: - Associated Object 접근

    private var currentTask: Task<Void, Never>? {
        objc_getAssociatedObject(base, &AssociatedKeys.task) as? Task<Void, Never>
    }

    private func setCurrentTask(_ task: Task<Void, Never>?) {
        objc_setAssociatedObject(base, &AssociatedKeys.task, task, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private var currentURL: URL? {
        objc_getAssociatedObject(base, &AssociatedKeys.url) as? URL
    }

    private func setCurrentURL(_ url: URL?) {
        objc_setAssociatedObject(base, &AssociatedKeys.url, url, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}

#endif
