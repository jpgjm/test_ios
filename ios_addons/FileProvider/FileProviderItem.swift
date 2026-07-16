//
//  FileProviderItem.swift
//  Music Player File Provider
//

import FileProvider
import UniformTypeIdentifiers

class FileProviderItem: NSObject, NSFileProviderItem {

    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    let capabilities: NSFileProviderItemCapabilities

    init(identifier: NSFileProviderItemIdentifier,
         parent: NSFileProviderItemIdentifier,
         filename: String,
         contentType: UTType,
         capabilities: NSFileProviderItemCapabilities) {
        self.itemIdentifier = identifier
        self.parentItemIdentifier = parent
        self.filename = filename
        self.contentType = contentType
        self.capabilities = capabilities
        super.init()
    }

    var itemVersion: NSFileProviderItemVersion {
        return NSFileProviderItemVersion(
            contentVersion: Data("1".utf8),
            metadataVersion: Data("1".utf8)
        )
    }

    // MARK: - Root item factory

    /// Files.appの側面板に出るルート「Music Player」フォルダのアイテム。
    /// capabilitiesを絞り込むことで削除・リネームを禁止し、
    /// 追加操作（capabilitiesにallowsAddingSubItemsを含める）だけ許可する。
    static func rootItem() -> FileProviderItem {
        return FileProviderItem(
            identifier: .rootContainer,
            parent: .rootContainer,
            filename: "Music Player",
            contentType: .folder,
            capabilities: [
                .allowsReading,
                .allowsContentEnumerating,
                .allowsAddingSubItems
                // 意図的に .allowsDeleting / .allowsRenaming / .allowsReparenting を含めない
                // → Files.appが赤マイナスマークを表示し、削除・リネームを拒否する
            ]
        )
    }
}
