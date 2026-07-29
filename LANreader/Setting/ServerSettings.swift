import SwiftUI
import ComposableArchitecture

struct ServerSettings: View {
    @Environment(NavigationHelper.self) private var navigation

        var body: some View {
        Button {
            navigation.push(UIServerListViewController(navigation: navigation))
        } label: {
            HStack {
                Text("server.list.title")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()

        Button {
            let store = Store(initialState: UploadFeature.State()) {
                UploadFeature()
            }
            navigation.push(UIUploadViewController(store: store))
        } label: {
            HStack {
                Text("settings.host.upload")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .foregroundStyle(.primary)
        .padding()
    }
}

struct ServerListSettingsView: View {
    @Environment(NavigationHelper.self) private var navigation
    @Dependency(\.lanraragiService) private var service

    @State private var servers = [LANraragiServer]()
    @State private var activeID: UUID?
    @State private var isActivating = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                Button {
                    openConfig(serverID: nil)
                } label: {
                    Label("server.list.add", systemImage: "plus.circle.fill")
                }
                .disabled(isActivating)
            }

            if servers.isEmpty {
                Section {
                    ContentUnavailableView(
                        "server.list.empty",
                        systemImage: "server.rack",
                        description: Text("server.list.empty.description")
                    )
                }
            } else {
                Section {
                    ForEach(servers) { server in
                        Button { activate(server) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(server.displayName).foregroundStyle(.primary)
                                    Text(server.url).font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if server.id == activeID {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .disabled(isActivating || server.id == activeID)
                        .swipeActions {
                            Button(role: .destructive) { delete(server) } label: {
                                Label("server.list.delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("server.list.title")
        .onAppear(perform: reload)
        .alert("error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("ok", role: .cancel) {}
        } message: { Text(errorMessage) }
    }

    private func reload() {
        servers = LANraragiServerStore.load()
        activeID = LANraragiServerStore.activeID()
    }

    private func openConfig(serverID: UUID?) {
        var state = LANraragiConfigFeature.State()
        state.serverID = serverID
        state.isAddingServer = serverID == nil
        let store = Store(initialState: state) { LANraragiConfigFeature() }
        navigation.push(UILANraragiConfigViewController(store: store, navigation: navigation))
    }

    private func activate(_ server: LANraragiServer) {
        isActivating = true
        Task {
            do {
                _ = try await service.verifyClient(url: server.url, apiKey: server.apiKey)
                LANraragiServerStore.activate(server)
                await MainActor.run {
                    servers = LANraragiServerStore.load()
                    activeID = server.id
                    isActivating = false
                }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isActivating = false }
            }
        }
    }

    private func delete(_ server: LANraragiServer) {
        let remaining = servers.filter { $0.id != server.id }
        LANraragiServerStore.save(remaining)
        if server.id == activeID {
            LANraragiServerStore.clearActive()
            activeID = nil
            servers = remaining
            Task {
                await service.clearClient()
                if let replacement = remaining.first {
                    await MainActor.run { activate(replacement) }
                }
            }
        } else {
            reload()
        }
    }
}

final class UIServerListViewController: UIViewController {
    private let navigationHelper: NavigationHelper

    init(navigation: NavigationHelper) {
        self.navigationHelper = navigation
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        let hostingController = UIHostingController(rootView: ServerListSettingsView().environment(navigationHelper))
        add(hostingController)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}
