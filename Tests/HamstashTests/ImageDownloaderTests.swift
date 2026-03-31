// ImageDownloaderTests.swift

import Testing
import Foundation
@testable import Hamstash

// MARK: - 테스트용 Mock URLProtocol

/// 네트워크 요청을 가로채서 미리 설정한 응답을 반환하는 Mock
final class MockURLProtocol: URLProtocol, @unchecked Sendable {

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handlers: [String: (Data?, HTTPURLResponse?, Error?)] = [:]

    static func setHandler(
        for url: String,
        data: Data?,
        response: HTTPURLResponse?,
        error: Error?
    ) {
        lock.lock()
        defer { lock.unlock() }
        _handlers[url] = (data, response, error)
    }

    static func handler(for url: String) -> (Data?, HTTPURLResponse?, Error?)? {
        lock.lock()
        defer { lock.unlock() }
        return _handlers[url]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url?.absoluteString else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        if let (data, response, error) = MockURLProtocol.handler(for: url) {
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
            } else {
                if let response {
                    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data {
                    client?.urlProtocol(self, didLoad: data)
                }
                client?.urlProtocolDidFinishLoading(self)
            }
        } else {
            // 핸들러가 없으면 빈 200 응답
            let emptyResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: emptyResponse, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

// MARK: - 헬퍼

private func makeTestDownloader() -> ImageDownloader {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: config)
    return ImageDownloader(session: session)
}

/// 고유한 테스트 URL을 생성한다 (병렬 테스트 충돌 방지).
private func uniqueURL(_ name: String = #function) -> URL {
    URL(string: "https://test.hamstash.dev/\(UUID().uuidString)/\(name).png")!
}

private func mockResponse(
    url: URL,
    data: Data = Data("image_data".utf8),
    statusCode: Int = 200
) {
    let response = HTTPURLResponse(
        url: url,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )
    MockURLProtocol.setHandler(for: url.absoluteString, data: data, response: response, error: nil)
}

private func mockError(url: URL, error: Error) {
    MockURLProtocol.setHandler(for: url.absoluteString, data: nil, response: nil, error: error)
}

// MARK: - 기본 다운로드

@Suite("ImageDownloader - 기본 동작")
struct ImageDownloaderBasicTests {

    @Test("URL로 이미지를 다운로드한다")
    func downloadFromURL() async throws {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        let expectedData = Data("test_image".utf8)
        mockResponse(url: url, data: expectedData)

        let data = try await downloader.download(from: url)

        #expect(data == expectedData)
    }

    @Test("URLRequest로 이미지를 다운로드한다")
    func downloadFromRequest() async throws {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        let expectedData = Data("test_image".utf8)
        mockResponse(url: url, data: expectedData)

        var request = URLRequest(url: url)
        request.setValue("Bearer token123", forHTTPHeaderField: "Authorization")

        let data = try await downloader.download(request: request)

        #expect(data == expectedData)
    }

    @Test("다운로드 성공 후 데이터가 비어있지 않다")
    func nonEmptyData() async throws {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        mockResponse(url: url, data: Data(repeating: 0xFF, count: 1024))

        let data = try await downloader.download(from: url)

        #expect(data.count == 1024)
    }
}

// MARK: - 에러 처리

@Suite("ImageDownloader - 에러 처리")
struct ImageDownloaderErrorTests {

    @Test("404 응답은 에러를 던진다")
    func notFound() async {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        mockResponse(url: url, statusCode: 404)

        await #expect(throws: DownloadError.self) {
            try await downloader.download(from: url)
        }
    }

    @Test("500 응답은 에러를 던진다")
    func serverError() async {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        mockResponse(url: url, statusCode: 500)

        await #expect(throws: DownloadError.self) {
            try await downloader.download(from: url)
        }
    }

    @Test("빈 데이터 응답은 에러를 던진다")
    func emptyData() async {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        mockResponse(url: url, data: Data(), statusCode: 200)

        await #expect(throws: DownloadError.self) {
            try await downloader.download(from: url)
        }
    }

    @Test("네트워크 에러 발생 시 에러가 전파된다")
    func networkError() async {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        mockError(url: url, error: error)

        await #expect(throws: Error.self) {
            try await downloader.download(from: url)
        }
    }
}

// MARK: - 중복 요청 병합

@Suite("ImageDownloader - 중복 요청 병합")
struct ImageDownloaderDeduplicationTests {

    @Test("같은 URL에 동시에 요청하면 모두 같은 데이터를 받는다")
    func sameResultForDuplicateRequests() async throws {
        let downloader = makeTestDownloader()
        let url = uniqueURL()
        let expectedData = Data("shared_image".utf8)
        mockResponse(url: url, data: expectedData)

        let results = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    try await downloader.download(from: url)
                }
            }

            var collected: [Data] = []
            for try await data in group {
                collected.append(data)
            }
            return collected
        }

        #expect(results.count == 5)
        for result in results {
            #expect(result == expectedData)
        }
    }

    @Test("다른 URL은 각각 독립적으로 다운로드된다")
    func differentURLsDownloadSeparately() async throws {
        let downloader = makeTestDownloader()
        let url1 = uniqueURL("a")
        let url2 = uniqueURL("b")
        let data1 = Data("image_a".utf8)
        let data2 = Data("image_b".utf8)

        mockResponse(url: url1, data: data1)
        mockResponse(url: url2, data: data2)

        async let result1 = downloader.download(from: url1)
        async let result2 = downloader.download(from: url2)

        let (r1, r2) = try await (result1, result2)

        #expect(r1 == data1)
        #expect(r2 == data2)
    }
}
