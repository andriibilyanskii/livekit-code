import Combine
import Foundation

class MainViewViewModel: ObservableObject {
    @Injected private var services: Services
    private var cancellables: Set<AnyCancellable> = .init()
    @Published var isAuthenticated: Bool = AuthenticationKeychainService
        .isAuthenticated
    @Published var isDeletedAccount: Bool = false

    private var settings: AppSettings?

    private var timerCancellable: AnyCancellable?

    @Published var roomModel: RoomModel?
    @Published var connectBookViewModel: ConnectBookViewModel?
    @Published var matchingViewModel: MatchingViewModel?
    @Published var eventsViewModel: EventsViewModel?
    @Published var profileViewModel: ProfileViewModel?
    @Published var settingsViewModel: SettingsViewModel?
    @Published var countryViewModel: CountryViewModel?

    init() {
        observeisAuthorized()
        setupModels()
        setupCentralTimer()
    }

    private var userId: String {
        return services.storageService.userProfile?.id ?? ""
    }

    private var token: String {
        return AuthenticationKeychainService.getToken() ?? ""
    }

    private var isUserAuthenticated: Bool {
        return !self.userId.isEmpty && !self.token.isEmpty
    }
}

extension MainViewViewModel {
    func setupModels() {
        self.setupSocketViewModel()
        self.setupConnectBookViewModel()
        self.setupMatchingViewModel()
        self.setupEventsViewModel()
        self.setupProfileViewModel()
        self.setupSettingsViewModel()
        self.setupCountryViewModel()
    }

    func destroyModels() {
        self.destroySocketViewModel()
        self.destroyConnectBookViewModel()
        self.destroyMatchingViewModel()
        self.destroyEventsViewModel()
        self.destroyProfileViewModel()
        self.destroySettingsViewModel()
        self.destroyCountryViewModel()
    }

    private func observeisAuthorized() {
        services.authenticationService.$isAuthenticated
            .sink { [weak self] value in
                self?.isAuthenticated = value

                if value {
                    self?.setupModels()
                    self?.setupCentralTimer()
                } else {
                    self?.destroyModels()
                    self?.destroyCentralTimer()
                }
            }
            .store(in: &cancellables)
    }

    func set(settings: AppSettings) {
        self.settings = settings
    }

    func setNotificationModelToViewModels(
        _ model: OrnamentNotificationModel
    ) {
        self.roomModel?.setNotificationModel(model)
        self.connectBookViewModel?.setNotificationModel(model)
        self.matchingViewModel?.setNotificationModel(model)
        self.eventsViewModel?.setNotificationModel(model)
        self.profileViewModel?.setNotificationModel(model)
        self.settingsViewModel?.setNotificationModel(model)
        self.countryViewModel?.setNotificationModel(model)
    }

    func setRoomModelToViewModels() {
        if let roomModel = roomModel {
            self.matchingViewModel?.bindSocket(roomModel)
            self.connectBookViewModel?.bindSocket(roomModel)
            self.eventsViewModel?.bindSocket(roomModel)
        }
    }

    func setSettingsViewModelToViewModels() {
        if let settingsViewModel = settingsViewModel {
            self.roomModel?.bindSettingsViewModel(settingsViewModel)
        }
    }
}

extension MainViewViewModel {
    // MARK: RoomModel

    private func setupSocketViewModel() {
        guard self.roomModel == nil else { return }

        if self.isAuthenticated && !self.userId.isEmpty {
            self.roomModel = RoomModel(userId: self.userId, token: self.token)
        } else {
            self.roomModel = nil
        }
    }

    private func destroySocketViewModel() {
        guard self.roomModel != nil else { return }

        self.roomModel?.destroySocket()
        self.roomModel = nil
    }

    func reloadSocketModel() {
        guard let user = services.storageService.userProfile,
            let token = AuthenticationKeychainService.getToken()
        else { return }

        services.authenticationService.logOut()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }

            services.authenticationService.setupTestAccount(model: user)
            AuthenticationKeychainService.updateToken(token: token)
        }
    }
}

extension MainViewViewModel {
    // MARK: ConnectBookViewModel

    private func setupConnectBookViewModel() {
        guard self.connectBookViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.connectBookViewModel = ConnectBookViewModel()
        } else {
            self.connectBookViewModel = nil
        }
    }

    private func destroyConnectBookViewModel() {
        guard self.connectBookViewModel != nil else { return }

        self.connectBookViewModel = nil
    }
}

extension MainViewViewModel {
    // MARK: MatchingViewModel

    private func setupMatchingViewModel() {
        guard self.matchingViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.matchingViewModel = MatchingViewModel()
        } else {
            self.matchingViewModel = nil
        }
    }

    private func destroyMatchingViewModel() {
        guard self.matchingViewModel != nil else { return }

        self.matchingViewModel = nil
    }
}

extension MainViewViewModel {
    // MARK: EventsViewModel

    private func setupEventsViewModel() {
        guard self.eventsViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.eventsViewModel = EventsViewModel()
        } else {
            self.eventsViewModel = nil
        }
    }

    private func destroyEventsViewModel() {
        guard self.eventsViewModel != nil else { return }

        self.eventsViewModel = nil
    }
}

extension MainViewViewModel {
    // MARK: ProfileViewModel

    private func setupProfileViewModel() {
        guard self.profileViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.profileViewModel = ProfileViewModel()
        } else {
            self.profileViewModel = nil
        }
    }

    private func destroyProfileViewModel() {
        guard self.profileViewModel != nil else { return }

        self.profileViewModel = nil
    }
}

extension MainViewViewModel {
    // MARK: SettingsViewModel

    private func setupSettingsViewModel() {
        guard self.settingsViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.settingsViewModel = SettingsViewModel()
        } else {
            self.settingsViewModel = nil
        }
    }

    private func destroySettingsViewModel() {
        guard self.settingsViewModel != nil else { return }

        self.settingsViewModel = nil
    }
}

extension MainViewViewModel {
    // MARK: CountryViewModel

    private func setupCountryViewModel() {
        guard self.countryViewModel == nil else { return }

        if self.isUserAuthenticated {
            self.countryViewModel = CountryViewModel()
        } else {
            self.countryViewModel = nil
        }
    }

    private func destroyCountryViewModel() {
        guard self.countryViewModel != nil else { return }

        self.countryViewModel = nil
    }
}

extension MainViewViewModel {
    func setupCentralTimer() {
//        guard timerCancellable == nil else { return }
//
//        let timer = Timer.publish(every: 5.0, on: .main, in: .common)
//            .autoconnect()
//
//        timerCancellable =
//            timer
//            .sink { [weak self] newDate in
//                self?.eventsViewModel?.handleTimerTick(newDate)
//            }
    }

    func destroyCentralTimer() {
        timerCancellable?.cancel()

        timerCancellable = nil
    }
}
