// HamstashImage.swift
// SwiftUI 이미지 뷰 — URL에서 자동 다운로드 + 캐싱

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// SwiftUI 이미지 뷰
///
/// URL에서 이미지를 자동으로 다운로드하고 캐싱한다.
/// `try await` 없이 선언형으로 사용할 수 있다.
///
/// ```swift
/// // 기본 사용법
/// HamstashImage(url)
///
/// // 커스텀 placeholder + 페이드 인
/// HamstashImage(url)
///     .placeholder { ProgressView() }
///     .fade(duration: 0.25)
///
/// // 헤더가 필요할 때
/// var request = URLRequest(url: url)
/// request.setValue("Bearer token", forHTTPHeaderField: "Authorization")
/// HamstashImage(request: request)
///
/// // 콜백
/// HamstashImage(url)
///     .onSuccess { data in print("loaded \(data.count) bytes") }
///     .onFailure { error in print("failed: \(error)") }
/// ```
public struct HamstashImage: View {

    // MARK: - 이미지 소스

    private enum Source: Equatable {
        case url(URL)
        case request(URLRequest)
        case none

        var key: String {
            switch self {
            case .url(let url): url.absoluteString
            case .request(let req): req.url?.absoluteString ?? ""
            case .none: ""
            }
        }

        static func == (lhs: Source, rhs: Source) -> Bool {
            lhs.key == rhs.key
        }
    }

    // MARK: - 로딩 상태

    private enum Phase: Equatable {
        case loading
        case success
        case failure
    }

    // MARK: - 설정

    private let source: Source
    private let storage: HamstashStorage
    private var _placeholder: AnyView
    private var _failure: AnyView
    private var _resizable: Bool
    private var _contentMode: ContentMode?
    private var _fadeDuration: Double?
    private var _onSuccess: (@Sendable (Data) -> Void)?
    private var _onFailure: (@Sendable (Error) -> Void)?

    // MARK: - 상태

    @State private var phase: Phase = .loading
    @State private var loadedImage: Image?

    // MARK: - 초기화

    /// URL로 이미지를 로드한다.
    /// - Parameters:
    ///   - url: 이미지 URL (nil이면 실패 뷰 표시)
    ///   - storage: 사용할 캐시 스토리지 (기본: `.default`)
    public init(_ url: URL?, storage: HamstashStorage = .default) {
        self.source = url.map { .url($0) } ?? .none
        self.storage = storage
        self._placeholder = AnyView(Color.gray.opacity(0.2))
        self._failure = AnyView(Image(systemName: "photo").foregroundStyle(.secondary))
        self._resizable = true
        self._contentMode = nil
        self._fadeDuration = nil
    }

    /// URLRequest로 이미지를 로드한다.
    ///
    /// 커스텀 헤더(Authorization, API Key 등)가 필요할 때 사용한다.
    /// - Parameters:
    ///   - request: 이미지 요청
    ///   - storage: 사용할 캐시 스토리지 (기본: `.default`)
    public init(request: URLRequest, storage: HamstashStorage = .default) {
        self.source = .request(request)
        self.storage = storage
        self._placeholder = AnyView(Color.gray.opacity(0.2))
        self._failure = AnyView(Image(systemName: "photo").foregroundStyle(.secondary))
        self._resizable = true
        self._contentMode = nil
        self._fadeDuration = nil
    }

    // MARK: - View

    public var body: some View {
        content
            .animation(
                _fadeDuration.map { .easeIn(duration: $0) },
                value: phase
            )
            .task(id: source.key) {
                guard source != .none else {
                    phase = .failure
                    return
                }
                await loadImage()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            _placeholder
        case .success:
            if let loadedImage {
                applyImageModifiers(loadedImage)
            } else {
                _failure
            }
        case .failure:
            _failure
        }
    }

    @ViewBuilder
    private func applyImageModifiers(_ image: Image) -> some View {
        if _resizable {
            if let mode = _contentMode {
                image.resizable().aspectRatio(contentMode: mode)
            } else {
                image.resizable()
            }
        } else {
            image
        }
    }

    // MARK: - 이미지 로딩

    private func loadImage() async {
        phase = .loading
        loadedImage = nil

        do {
            let data: Data
            switch source {
            case .url(let url):
                data = try await storage.image(from: url)
            case .request(let request):
                data = try await storage.image(request: request)
            case .none:
                phase = .failure
                return
            }

            guard let image = Self.createImage(from: data) else {
                phase = .failure
                _onFailure?(DownloadError.invalidImageData)
                return
            }

            loadedImage = image
            phase = .success
            _onSuccess?(data)
        } catch {
            phase = .failure
            _onFailure?(error)
        }
    }

    // MARK: - 플랫폼별 이미지 생성

    private static func createImage(from data: Data) -> Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(data: data) else { return nil }
        return Image(uiImage: uiImage)
        #elseif canImport(AppKit)
        guard let nsImage = NSImage(data: data) else { return nil }
        return Image(nsImage: nsImage)
        #else
        return nil
        #endif
    }

    // MARK: - Builder 메서드

    /// 로딩 중 표시할 뷰를 설정한다.
    ///
    /// ```swift
    /// HamstashImage(url)
    ///     .placeholder { ProgressView() }
    /// ```
    public func placeholder<P: View>(@ViewBuilder _ content: () -> P) -> HamstashImage {
        var copy = self
        copy._placeholder = AnyView(content())
        return copy
    }

    /// 로딩 실패 시 표시할 뷰를 설정한다.
    ///
    /// ```swift
    /// HamstashImage(url)
    ///     .onFailureImage { Image(systemName: "exclamationmark.triangle") }
    /// ```
    public func onFailureImage<F: View>(@ViewBuilder _ content: () -> F) -> HamstashImage {
        var copy = self
        copy._failure = AnyView(content())
        return copy
    }

    /// 이미지를 resizable로 설정한다 (기본: true).
    public func resizable(_ resizable: Bool = true) -> HamstashImage {
        var copy = self
        copy._resizable = resizable
        return copy
    }

    /// 이미지 콘텐츠 모드를 설정한다.
    ///
    /// ```swift
    /// HamstashImage(url)
    ///     .aspectRatio(contentMode: .fit)
    /// ```
    public func aspectRatio(contentMode: ContentMode) -> HamstashImage {
        var copy = self
        copy._contentMode = contentMode
        return copy
    }

    /// 페이드 인 애니메이션을 설정한다.
    ///
    /// ```swift
    /// HamstashImage(url)
    ///     .fade(duration: 0.25)
    /// ```
    public func fade(duration: Double = 0.25) -> HamstashImage {
        var copy = self
        copy._fadeDuration = duration
        return copy
    }

    /// 이미지 로딩 성공 시 호출되는 콜백을 설정한다.
    public func onSuccess(_ action: @escaping @Sendable (Data) -> Void) -> HamstashImage {
        var copy = self
        copy._onSuccess = action
        return copy
    }

    /// 이미지 로딩 실패 시 호출되는 콜백을 설정한다.
    public func onFailure(_ action: @escaping @Sendable (Error) -> Void) -> HamstashImage {
        var copy = self
        copy._onFailure = action
        return copy
    }
}
