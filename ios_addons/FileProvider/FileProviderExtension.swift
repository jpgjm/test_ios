//
//  FileProviderExtension.swift
//  Music Player File Provider
//
//  フェーズ1: Files.appの側面板に「Music Player」を出現させる最小実装。
//  子要素は空、削除・リネームは不可、追加は許可のcapabilitiesで
//  ルートフォルダを1つだけ持つ。実データの読み書きは未実装。
//

import FileProvider

@objc(FileProviderExtension)
class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {

    let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
        super.init()
    }

    func invalidate() {
        // クリーンアップが必要ならここに
    }

    // MARK: - Item lookup

    func item(for identifier: NSFileProviderItemIdentifier,
              request: NSFileProviderRequest,
              completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        if identifier == .rootContainer {
            completionHandler(FileProviderItem.rootItem(), nil)
        } else {
            completionHandler(nil, NSFileProviderError(.noSuchItem))
        }
        return Progress()
    }

    // MARK: - Content fetch (フェーズ1では実データ無し)

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier,
                       version requestedVersion: NSFileProviderItemVersion?,
                       request: NSFileProviderRequest,
                       completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        completionHandler(nil, nil, NSFileProviderError(.noSuchItem))
        return Progress()
    }

    // MARK: - Create / Modify / Delete (フェーズ1では全て拒否)

    func createItem(basedOn itemTemplate: NSFileProviderItem,
                    fields: NSFileProviderItemFields,
                    contents url: URL?,
                    options: NSFileProviderCreateItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        // フェーズ2で実装
        completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem,
                    baseVersion version: NSFileProviderItemVersion,
                    changedFields: NSFileProviderItemFields,
                    contents newContents: URL?,
                    options: NSFileProviderModifyItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, NSFileProviderError(.serverUnreachable))
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier,
                    baseVersion version: NSFileProviderItemVersion,
                    options: NSFileProviderDeleteItemOptions,
                    request: NSFileProviderRequest,
                    completionHandler: @escaping (Error?) -> Void) -> Progress {
        // ルートはcapabilitiesで削除禁止しているが、念のため拒否
        completionHandler(NSFileProviderError(.deletionRejected))
        return Progress()
    }

    // MARK: - Enumerator

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier,
                    request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        return FileProviderEnumerator(containerIdentifier: containerItemIdentifier)
    }
}
