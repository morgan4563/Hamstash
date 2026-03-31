// KeyHasherTests.swift

import Testing
import Foundation
@testable import Hamstash

@Suite("KeyHasher")
struct KeyHasherTests {

    @Test("동일한 입력은 항상 동일한 해시를 반환한다")
    func deterministic() {
        let hash1 = KeyHasher.sha256("hello")
        let hash2 = KeyHasher.sha256("hello")

        #expect(hash1 == hash2)
    }

    @Test("다른 입력은 다른 해시를 반환한다")
    func differentInputs() {
        let hash1 = KeyHasher.sha256("hello")
        let hash2 = KeyHasher.sha256("world")

        #expect(hash1 != hash2)
    }

    @Test("해시 결과는 64자리 hex 문자열이다")
    func outputLength() {
        let hash = KeyHasher.sha256("test")

        #expect(hash.count == 64)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("빈 문자열도 해싱할 수 있다")
    func emptyString() {
        let hash = KeyHasher.sha256("")

        #expect(hash.count == 64)
    }

    @Test("URL 문자열이 안전하게 해싱된다")
    func urlString() {
        let hash = KeyHasher.sha256("https://example.com/image.png?size=large&quality=high")

        #expect(hash.count == 64)
        #expect(!hash.contains("/"))
        #expect(!hash.contains("?"))
        #expect(!hash.contains("&"))
    }

    @Test("한글 키가 안전하게 해싱된다")
    func koreanString() {
        let hash = KeyHasher.sha256("프로필_이미지_123")

        #expect(hash.count == 64)
    }

    @Test("매우 긴 키도 64자리로 해싱된다")
    func longString() {
        let longKey = String(repeating: "a", count: 10000)
        let hash = KeyHasher.sha256(longKey)

        #expect(hash.count == 64)
    }
}
