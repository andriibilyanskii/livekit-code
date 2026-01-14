@preconcurrency import LiveKit
import SwiftUI
import UIKit

private struct SelectionKey: EnvironmentKey {
    static let defaultValue: Int = 7
}

extension EnvironmentValues {
    var selection: Int {
        get { self[SelectionKey.self] }
        set { self[SelectionKey.self] = newValue }
    }
}

struct MainView: View {
    @Injected private var services: Services

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var soundService: SoundService
    @EnvironmentObject private var notificationModel: OrnamentNotificationModel
    @EnvironmentObject private var settingsViewModel: SettingsViewModel

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow

    @ObservedObject private var viewModel: MainViewViewModel = .init()

    @State var selection = 7
    @State private var disconnectTimer: Task<Void, Never>? = nil
    @State private var bgTaskID: UIBackgroundTaskIdentifier = .invalid

    @StateObject private var room: Room

    init() {
        let room = Room()
        _room = StateObject(wrappedValue: room)
    }

    var body: some View {
        Group {
            if let socketVM = viewModel.roomModel,
                let connectBookVM = viewModel.connectBookViewModel,
                let matchingVM = viewModel.matchingViewModel,
                let eventsVM = viewModel.eventsViewModel,
                let profileVM = viewModel.profileViewModel,
                let settingsVM = viewModel.settingsViewModel,
                let countryVM = viewModel.countryViewModel
            {
                mainContent
                    .environmentObject(socketVM)
                    .environmentObject(connectBookVM)
                    .environmentObject(matchingVM)
                    .environmentObject(eventsVM)
                    .environmentObject(profileVM)
                    .environmentObject(settingsVM)
                    .environmentObject(countryVM)
                    .environment(\.selection, selection)
                    .onAppear {
                        viewModel
                            .setNotificationModelToViewModels(
                                notificationModel
                            )

                        viewModel.setRoomModelToViewModels()
                        viewModel.setSettingsViewModelToViewModels()

                        viewModel.matchingViewModel?.attachRoom(room)
                    }
            } else {
                mainContent
            }
        }
        .environmentObject(room)
        .onAppear {
            self.onAppearFunc()
        }
        .onChange(of: viewModel.isAuthenticated) { _, newState in
            if !newState, room.connectionState != .disconnected {
                Task {
                    await room.disconnect()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .didChangeCallStatus
            )
        ) { notification in
            if let connected = notification.userInfo?["connected"] as? Bool {
                if connected {
                    self.selection = 2

                    if let matchingVM = viewModel.matchingViewModel {
                        matchingVM
                            .changeConnectionState(
                                .searching,
                                connectionType: .global
                            )
                    }
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .didPressOpenMeetView
            )
        ) { _ in
            self.selection = 2
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if viewModel.roomModel != nil,
                viewModel.connectBookViewModel != nil,
                viewModel.matchingViewModel != nil,
                viewModel.eventsViewModel != nil,
                viewModel.profileViewModel != nil,
                viewModel.settingsViewModel != nil,
                viewModel.countryViewModel != nil
            {
                if !services.authenticationService.isAuthenticated {
                    authLobbyView
                } else if appState.isRegisterProfile {
                    createProfileView
                } else {
                    MatchingWrapperView {
                        TabView(selection: $selection) {
                            mixerEventsView
                            connectBook
                            meet
                            profile
                            settingsView
                        }
                        #if os(visionOS)
                            .frame(
                                width: settings.windowWidth,
                                height: settings.windowHeight
                            )
                            .clipped()
                        #endif
                    }
                }
            } else {
                authLobbyView
            }
        }
        .onChange(
            of: services.authenticationService.isAuthenticated,
            initial: true
        ) {
            _,
            isAuth in
            self.handleChangeIsAuthenticated(isAuth: isAuth)
        }
        .animation(.default, value: viewModel.isAuthenticated)
        .onChange(of: selection) { _, newActiveTag in
            services.navigationService.activeTag = newActiveTag
        }
    }
}

extension MainView {
    private var connectBook: some View {
        ConnectBookView()
    }

    private var meet: some View {
        MatchingView()
    }

    private var profile: some View {
        ProfileView()
    }

    private var settingsView: some View {
        SettingsView()
    }

    private var createProfileView: some View {
        CreateProfileView()
    }

    private var authLobbyView: some View {
        AuthLobbyView()
    }

    private var mixerEventsView: some View {
        MixerEventsView()
    }
}

extension MainView {
    private func onAppearFunc() {
        services.authenticationService.getMyUserInfo()
    }

    private func handleChangeIsAuthenticated(isAuth: Bool) {
        if isAuth {
            let languages = services.storageService.userProfile?
                .languagesForMatching

            let avatarUrl =
                services.storageService.userProfile?
                .avatarUrl ?? ""

            var checkAvatar = avatarUrl.isEmpty

            #if targetEnvironment(simulator)
                checkAvatar = false
            #endif

            if let fullName = services.storageService.userProfile?.fullName,
                let nickname = services.storageService.userProfile?
                    .nickname,
                fullName.isEmpty
                    || nickname.isEmpty
                    || (languages?.isEmpty ?? true)
                    || checkAvatar
            {
                appState.isRegisterProfile = true
            } else {
                selection = 7
            }
        }
    }
}
