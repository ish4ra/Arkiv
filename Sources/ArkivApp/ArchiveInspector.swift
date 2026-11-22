import AppKit
import ArkivCore

/// Snapshot-only inspector; showing it performs no extraction or password lookup.
final class ArchiveInspector: NSWindowController {
    init(metadata: ArchiveMetadata, icon: NSImage? = nil) {
        let panel = NSPanel(contentRect:NSRect(x:0,y:0,width:520,height:360),styleMask:[.titled,.closable],backing:.buffered,defer:false)
        super.init(window:panel)
        panel.title = "Archive Info"
        let grid = NSGridView(views:Self.rows(metadata).map { title,value in
            let label = NSTextField(labelWithString:title)
            label.textColor = .secondaryLabelColor
            let field = NSTextField(wrappingLabelWithString:value)
            field.isSelectable = true; field.setAccessibilityLabel(title)
            field.widthAnchor.constraint(lessThanOrEqualToConstant:360).isActive = true
            return [label,field]
        })
        grid.rowSpacing = 8; grid.columnSpacing = 16
        grid.column(at:0).xPlacement = .trailing
        let done = NSButton(title:"Done",target:self,action:#selector(dismissInspector))
        done.keyEquivalent = "\r"
        var top: NSView = grid
        if let icon {
            // The selected document icon theme's artwork for this format.
            let image = NSImageView(image:icon)
            image.imageScaling = .scaleProportionallyUpOrDown
            image.setAccessibilityElement(false)
            image.widthAnchor.constraint(equalToConstant:64).isActive = true
            image.heightAnchor.constraint(equalToConstant:64).isActive = true
            let row = NSStackView(views:[image,grid]); row.alignment = .top; row.spacing = 16
            top = row
        }
        let content = NSStackView(views:[top,done]); content.orientation = .vertical
        content.alignment = .trailing; content.spacing = 18
        content.edgeInsets = NSEdgeInsets(top:20,left:20,bottom:20,right:20)
        panel.contentView = content; panel.setContentSize(content.fittingSize)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) unavailable") }
    @objc private func dismissInspector() { if let window, let parent = window.sheetParent { parent.endSheet(window) }; close() }
    static func rows(_ m: ArchiveMetadata) -> [(String,String)] {
        func size(_ bytes:UInt64) -> String { ByteCountFormatter.string(fromByteCount:Int64(clamping:bytes),countStyle:.file) + " (\(bytes) bytes)" }
        var rows = [("Name",m.url.lastPathComponent),("Path",m.url.path)]
        if let format = m.format { rows.append(("Format",format)) }
        rows += [("Archive size",size(m.physicalSize)),("Files",String(m.fileCount)),("Folder entries",String(m.folderCount))]
        if let total = m.unpackedSize { rows.append(("Unpacked size",size(total))) }
        if let ratio = m.sizeRatio { rows.append(("Archive / unpacked",String(format:"%.1f%% (includes overhead)",ratio*100))) }
        if let methods = m.compressionMethods { rows.append(("Methods",methods)) }
        for (name,value) in [("Solid",m.solid),("Data encrypted",m.dataEncrypted),("Filenames encrypted",m.headersEncrypted),("Multipart",m.multipart)] {
            if let value { rows.append((name,value ? "Yes" : "No")) }
        }
        return rows
    }
}
