import Foundation

enum TextEncoding {
    static func readContent(from url: URL) throws -> String {
        if let raw = try? String(contentsOf: url, encoding: .utf8) {
            return raw
        }
        let gbk = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let ns = CFStringConvertEncodingToNSStringEncoding(gbk)
        if let raw = try? String(contentsOf: url, encoding: String.Encoding(rawValue: ns)) {
            return raw
        }
        throw NSError(domain: "TextEncoding", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "无法识别文件编码，请使用 UTF-8 或 GBK 格式"])
    }
}
