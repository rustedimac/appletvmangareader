import SwiftUI
import MangaCore

/// Settings → Content & PIN, for the active profile: the profile's PIN, an
/// age limit, hidden genres and tags, and which libraries/categories each
/// server imports. Opened through `PINGate`, so a profile with a PIN asks
/// for it first. Every change saves right away.
struct ContentSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var facets: ContentFacets?

    private var profile: Profile { model.activeProfile }
    private var filter: ContentFilter { model.contentFilter }

    var body: some View {
        List {
            pinSection
            ageSection
            listSection(title: "Hidden Genres", names: facets?.genres, kind: "genre",
                        isHidden: filter.isGenreHidden) { name, hidden in
                var f = filter
                f.setGenre(name, hidden: hidden)
                model.setContentFilter(f)
            }
            if let tags = facets?.tags, !tags.isEmpty {
                listSection(title: "Hidden Tags", names: tags, kind: "tag", isHidden: filter.isTagHidden) { name, hidden in
                    var f = filter
                    f.setTag(name, hidden: hidden)
                    model.setContentFilter(f)
                }
            }
            if !model.servers.isEmpty {
                Section {
                    ForEach(model.servers) { server in
                        NavigationLink {
                            CategorySelectionView(server: server)
                        } label: {
                            HStack {
                                Text(server.name)
                                Spacer()
                                Text(model.selectedCategories(for: server).map { "\($0.count) picked" } ?? "All")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("content.categories.\(server.name)")
                    }
                } header: {
                    Text("Libraries and Categories")
                } footer: {
                    Text("Untick a Kavita library or Suwayomi category to hide all of it from \(profile.name).")
                }
            }
        }
        .navigationTitle("Content & PIN")
        .task { facets = await model.contentFacets() }
    }

    // MARK: PIN

    @ViewBuilder
    private var pinSection: some View {
        Section {
            if model.hasPIN(profile.id) {
                NavigationLink {
                    PINSetupView(profileName: profile.name) { model.setPIN($0, for: profile.id) }
                } label: {
                    Label("Change PIN", systemImage: "lock.rotation")
                }
                .accessibilityIdentifier("content.changePIN")

                checkRow("Ask for PIN to Open \(profile.name)", isOn: model.requiresPINToOpen(profile.id),
                         id: "content.requirePIN") {
                    model.setRequiresPINToOpen(!model.requiresPINToOpen(profile.id), profile: profile.id)
                }

                Button(role: .destructive) {
                    model.setPIN(nil, for: profile.id)
                } label: {
                    Label("Remove PIN", systemImage: "lock.open")
                }
                .accessibilityIdentifier("content.removePIN")
            } else {
                NavigationLink {
                    PINSetupView(profileName: profile.name) { model.setPIN($0, for: profile.id) }
                } label: {
                    Label("Set PIN", systemImage: "lock")
                }
                .accessibilityIdentifier("content.setPIN")
            }
        } header: {
            Text("PIN for \(profile.name)")
        } footer: {
            Text(model.hasPIN(profile.id)
                 ? "The PIN is needed to change these settings, this profile, servers, or to add a profile. For a child's profile, leave \"Ask for PIN to Open\" off so they can still read."
                 : "Without a PIN, anyone using this profile can change what it shows.")
        }
    }

    // MARK: Age limit

    @ViewBuilder
    private var ageSection: some View {
        if facets?.supportsAgeRating == true || filter.maxAgeRating != nil {
            Section {
                checkRow("No Limit", isOn: filter.maxAgeRating == nil, id: "content.age.none") {
                    var f = filter
                    f.maxAgeRating = nil
                    f.hideUnrated = false
                    model.setContentFilter(f)
                }
                ForEach(AgeRating.limitChoices) { rating in
                    checkRow("Up to \(rating.title)", isOn: filter.maxAgeRating == rating,
                             id: "content.age.\(rating.rawValue)") {
                        var f = filter
                        f.maxAgeRating = rating
                        model.setContentFilter(f)
                    }
                }
                if filter.maxAgeRating != nil {
                    checkRow("Also Hide Series Without a Rating", isOn: filter.hideUnrated, id: "content.age.hideUnrated") {
                        var f = filter
                        f.hideUnrated.toggle()
                        model.setContentFilter(f)
                    }
                }
            } header: {
                Text("Age Limit")
            } footer: {
                Text("Uses Kavita's age ratings. Suwayomi has none, so hide its categories or genres instead.")
            }
        }
    }

    // MARK: Genres and tags

    @ViewBuilder
    private func listSection(title: String, names: [String]?, kind: String, isHidden: @escaping (String) -> Bool,
                             set: @escaping (String, Bool) -> Void) -> some View {
        Section {
            if let names {
                if names.isEmpty {
                    Text("Your servers don't list any \(kind)s.").foregroundStyle(.secondary)
                }
                ForEach(names, id: \.self) { name in
                    let hidden = isHidden(name)
                    Button {
                        set(name, !hidden)
                    } label: {
                        HStack {
                            Text(name)
                            Spacer()
                            Image(systemName: hidden ? "eye.slash.fill" : "eye")
                                .foregroundStyle(hidden ? Color.red : .secondary)
                        }
                    }
                    .accessibilityIdentifier("content.\(kind).\(name)")
                    .accessibilityValue(hidden ? "hidden" : "shown")
                }
            } else {
                HStack {
                    Text("Loading \(kind)s…").foregroundStyle(.secondary)
                    Spacer()
                    ProgressView()
                }
            }
        } header: {
            Text(title)
        } footer: {
            Text("Series with a hidden \(kind) disappear from Home, Library, Search and Favorites.")
        }
    }

    private func checkRow(_ title: String, isOn: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isOn { Image(systemName: "checkmark").foregroundStyle(Color.accentColor) }
            }
        }
        .accessibilityIdentifier(id)
        .accessibilityValue(isOn ? "on" : "off")
    }
}
