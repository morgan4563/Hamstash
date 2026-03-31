// KeyHasher.swift
// 캐시 키를 파일명으로 안전하게 변환하는 해싱 유틸리티

import Foundation
import CryptoKit

/// 캐시 키를 파일명으로 안전하게 변환한다.
///
/// URL 문자열 같은 키에는 `/`, `?`, `&` 등 파일명에 사용할 수 없는 문자가 포함될 수 있다.
/// SHA256 해시로 변환하면 고정 길이의 안전한 파일명을 얻을 수 있다.
///
/// ```swift
/// KeyHasher.sha256("https://example.com/image.png?size=large")
/// // → "a1b2c3d4..."  (64자리 hex 문자열)
/// ```
enum KeyHasher {

    /// 문자열 키를 SHA256 해시로 변환한다.
    /// - Parameter key: 원본 캐시 키
    /// - Returns: 64자리 hex 문자열
    static func sha256(_ key: String) -> String {
        let data = Data(key.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
