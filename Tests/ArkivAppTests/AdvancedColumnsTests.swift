import AppKit
import XCTest
import ArkivCore
@testable import ArkivApp
final class AdvancedColumnsTests: XCTestCase {
    @MainActor func testCellsRenderUnknownBlankAndAlignNumbers() {
        let row = ArchiveIndex(entries:[.init(id:0,path:"file",size:100,kind:.file)]).children(of:"")[0]
        for key in ["packed","ratio","modified","method","encrypted"] {
            let cell = ArchiveCellView(column:key)
            cell.configure(row,column:key,searching:false)
            XCTAssertEqual(cell.textField?.stringValue,"")
            XCTAssertEqual(cell.textField?.alignment,["packed","ratio"].contains(key) ? .right : .left)
        }
    }
}
