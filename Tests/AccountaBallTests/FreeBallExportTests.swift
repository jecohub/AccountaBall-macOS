import Foundation
@testable import AccountaBall

func runFreeBallExportTests() {
    suite("FreeBallExport_filename") {
        let name = FreeBallExport.filename(for: Date(timeIntervalSince1970: 0))
        expect(name.hasSuffix(".md"), "is a markdown file")
        expect(name.hasPrefix("freeball-"), "prefixed")
    }
}
