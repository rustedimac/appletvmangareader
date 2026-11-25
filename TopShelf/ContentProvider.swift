import Foundation
import TVServices
import MangaCore

/// The Top Shelf extension. It runs with a small memory limit, so it only
/// reads the snapshot and cover files the app writes to the App Group
/// (`TopShelfPublisher`) and never talks to a server.
final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent(completionHandler: @escaping ((any TVTopShelfContent)?) -> Void) {
        guard let store = TopShelfStore.shared, let snapshot = store.load(), !snapshot.sections.isEmpty else {
            completionHandler(nil)
            return
        }
        let sections = snapshot.sections.map { section -> TVTopShelfItemCollection<TVTopShelfSectionedItem> in
            let items = section.items.map { entry -> TVTopShelfSectionedItem in
                let item = TVTopShelfSectionedItem(identifier: entry.id)
                item.title = entry.title
                item.imageShape = .poster
                if let file = entry.coverFile, store.hasCover(file) {
                    item.setImageURL(store.coverURL(file), for: [.screenScale1x, .screenScale2x])
                }
                item.displayAction = TVTopShelfAction(url: entry.displayURL)
                item.playAction = TVTopShelfAction(url: entry.playURL)
                return item
            }
            let collection = TVTopShelfItemCollection(items: items)
            collection.title = section.title
            return collection
        }
        completionHandler(TVTopShelfSectionedContent(sections: sections))
    }
}
