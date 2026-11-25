import SwiftUI
import MangaCore

struct LibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PlaceholderView(title: "Library", message: "Browse each server's libraries and categories.")
    }
}
