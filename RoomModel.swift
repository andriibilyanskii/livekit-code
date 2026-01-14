import Combine
import SwiftUI

struct RoomResponseModel: Codable {
    let roomId: String
    let myInfo: UserProfileModel
    let partners: [UserProfileModel]
    let myLiveKitToken: String
    let eventId: String?

    enum CodingKeys: String, CodingKey {
        case roomId = "roomId"
        case myInfo = "myInfo"
        case partners = "partners"
        case myLiveKitToken = "myLiveKitToken"
        case eventId = "eventId"
    }
}

final class RoomModel: Notifiable, ObservableObject {
    @Injected var services: Services

    private var cancellables: Set<AnyCancellable> = Set()

    var globalManager: RoomGlobalManager?
    //    var invitesManager: RoomInvitesManager?
    //    var eventsManager: RoomEventsManager?

    @Published private(set) var socketConnected: Bool = false
    @Published private(set) var shouldCall: Bool = false

    @Published private(set) var roomId: String = ""
    @Published private(set) var myInfo: UserProfileModel?
    @Published private(set) var partners: [UserProfileModel] = []
    @Published private(set) var joinedVideoPartners: [String] = []
    @Published private(set) var myLiveKitToken: String = ""

    @Published private(set) var timerValue: Int = -1
    @Published private(set) var hasExtendedTimer: Bool = false
    @Published private(set) var currentMaxTimerValue: Int = AppSettings
        .callTimerValue

    @Published private(set) var sentConnectUserRequests: [String] = []
    @Published private var partnersSentConnectUserRequest: [String] = []
    @Published private var friendsUsers: [String] = []

    @Published private var usersOnline: [UserOnlineStatusModel] = []

    private let socketService = SocketIOService.shared
    private let userId: String
    private let token: String

    init(userId: String, token: String) {
        self.userId = userId
        self.token = token

        setupManagers()
        socketService.initSocket(userId: userId, token: token)
    }

    private func setupManagers() {
        self.globalManager = RoomGlobalManager(
            roomModel: self,
            userId: userId,
            token: token
        )
        //        self.invitesManager = RoomInvitesManager(roomModel: self)
        //        self.eventsManager = RoomEventsManager(roomModel: self)

        self.bindService()
    }

    var notificationModel: OrnamentNotificationModel?

    func setNotificationModel(_ model: OrnamentNotificationModel) {
        self.notificationModel = model
    }

    func destroySocket() {
        socketService.disconnectAndDestroy()
    }

    func reset() {
        roomId = ""
        myInfo = nil
        partners = []
        joinedVideoPartners = []
        myLiveKitToken = ""
        timerValue = -1
        hasExtendedTimer = false
        currentMaxTimerValue = AppSettings.callTimerValue
    }

    private(set) var settingsViewModel: SettingsViewModel?

    func bindSettingsViewModel(_ settingsViewModel: SettingsViewModel) {
        self.settingsViewModel = settingsViewModel
    }
}

// MARK: Variables
extension RoomModel {
    var myId: String {
        services.storageService.userProfile?.id ?? ""
    }

    func isUsersFriends(userId: String) -> Bool {
        return !userId.isEmpty
            && (self.friendsUsers.contains(userId)
                || self.sentConnectUserRequests.contains(userId)
                    && self.partnersSentConnectUserRequest.contains(userId))
    }

    func getFriendStatus(user: ConnectBookUserModel) -> FriendsStatus {
        if user.isFriend == true
            || self.isUsersFriends(
                userId: user.computedId
            )
        {
            return .friends
        } else if user.isPendingConnectRequest == true
            || self.sentConnectUserRequests.contains(
                user.computedId
            )
        {
            return .connecting
        } else {
            return .notFriends
        }
    }

    func isPartnerJoinedVideo(userId: String) -> Bool {
        return !userId.isEmpty && self.joinedVideoPartners.contains(userId)
    }

    func isUserOnline(_ userId: String) -> Bool {
        self.usersOnline.contains { $0.userId == userId }
    }

    func getUserOnlineStatus(_ userId: String?) -> UserOnlineStatus {
        self.usersOnline
            .first(where: { $0.userId == userId })?.status
            ?? .offline
    }

    func getUserOnlineStatusModel(_ userId: String?) -> UserOnlineStatusModel? {
        self.usersOnline.first(where: { $0.userId == userId })
    }

    var onlineUsersCount: Int {
        self.usersOnline.count(where: { $0.status != .offline })
    }

    var onlineFriendsCount: Int {
        self.usersOnline.count(where: {
            $0.status != .offline  // && self.friendsUsers.contains($0.userId)
        })
    }

    var friendsUsersCount: Int {
        self.friendsUsers.count
    }
}

extension RoomModel {
    // MARK: Matching

    func changeShouldCall(_ shouldCall: Bool) {
        self.shouldCall = shouldCall
        socketService.changeShouldCall(shouldCall: shouldCall)

        UIApplication.shared.isIdleTimerDisabled = shouldCall
    }

    func endCall() {
        self.changeShouldCall(false)
        socketService.sendEnd()
        self.reset()
    }

    func joinedVideo() {
        socketService
            .joinedVideo(
                roomId: self.roomId,
                meetTime: self.currentMaxTimerValue
            )
    }

    // MARK: Timer

    func extendTimer(seconds: Int) {
        socketService.extendTimer(to: self.roomId, seconds: seconds)
        self.hasExtendedTimer = true
    }

    // MARK: Users Online

    func changeUserOnline(
        isOnline: Bool,
        isBusy: Bool,
        completion: ((_ response: Any) -> Void)? = nil
    ) {
        socketService
            .changeUserOnline(
                isOnline: isOnline,
                isBusy: isBusy,
                completion: completion
            )
    }

    private func getUsersOnline(dict: Any) {
        guard let userOnlineInfo = RoomModel.decodeUserOnlineInfo(from: dict)
        else { return }

        self.updateUserStatus(userOnlineInfo)
    }

    private func updateUserStatus(_ userStatuses: [UserOnlineStatusModel]) {
        for userOnlineStatus in userStatuses {
            if let index = self.usersOnline.firstIndex(of: userOnlineStatus) {
                usersOnline[index] = userOnlineStatus
            } else {
                usersOnline.append(userOnlineStatus)
            }
        }
    }

    // MARK: Connect Book

    func connectUserRequest(user: UserRepresentable) {
        socketService.connectUserRequest(
            userId: user.computedId,
            completion: { [weak self] completionStatus, data in
                guard completionStatus as! Bool == true else { return }

                if let data = data as? [String: Any],
                    let isFriends = data["isFriends"] as? Bool,
                    isFriends
                {
                    self?.friendsUsers.append(user.computedId)

                    if self?.settingsViewModel?.audioSettings?.allSounds == true
                    {
                        self?.services.soundService.playSound(
                            named: "Friend-Accepted",
                            duration: 3
                        )
                    }

                    self?.notificationModel?.showNotification(
                        OrnamentNotification(
                            title: "Partner has accepted your connection",
                            type: .success,
                            contentView: {
                                AnyView(
                                    AcceptedConnectionNotificationContentView(
                                        user: user
                                    )
                                )
                            }
                        )
                    )

                    NotificationCenter.default.post(
                        name: .didAddFriend,
                        object: nil,
                        userInfo: nil
                    )
                } else {
                    self?.sentConnectUserRequests.append(user.computedId)

                    if self?.settingsViewModel?.audioSettings?.allSounds == true
                    {
                        self?.services.soundService.playSound(
                            named: "friend-request",
                            duration: 3
                        )
                    }
                }
            }
        )
    }

    func cancelConnectUserRequest(
        userId: String,
        completion: SocketAckCompletion?
    ) {
        socketService.cancelConnectUserRequest(
            userId: userId,
            completion: { [weak self] completionStatus, data in
                guard completionStatus as! Bool == true else { return }

                self?.sentConnectUserRequests.removeAll(where: { $0 == userId })

                completion?(completionStatus, data)
            }
        )
    }

    func removeUserRequest(
        userId: String,
        completion: SocketAckCompletion?
    ) {
        socketService.removeUserRequest(userId: userId, completion: completion)
    }

    func removeFriendLocal(userId: String) {
        self.partnersSentConnectUserRequest.removeAll(where: { $0 == userId })
        self.sentConnectUserRequests.removeAll(where: { $0 == userId })
        self.friendsUsers.removeAll(where: { $0 == userId })
    }

    // MARK: Listeners

    private func bindService() {
        socketService.onSocketConnected = { [weak self] in
            self?.socketConnected = true

            self?.changeUserOnline(
                isOnline: true,
                isBusy: false,
                completion: self?.getUsersOnline
            )
        }

        socketService.onSocketDisconnected = { [weak self] in
            self?.socketConnected = false
            self?.shouldCall = false
        }

        socketService.onShowNotification = { [weak self] payload in
            guard let self = self else { return }

            let notificationInfo = RoomModel.decodeNotificationInfo(
                from: payload
            )

            guard let notificationInfo = notificationInfo else { return }

            self.notificationModel?.showNotification(
                OrnamentNotification(
                    title: notificationInfo.text,
                    message: notificationInfo.description,
                    type: notificationInfo.type,
                    customData: [
                        "roomId": self.roomId,
                        "hideOnEndCall": notificationInfo.hideOnEndCall
                            ?? false,
                    ],
                    customDuration: notificationInfo.customDuration
                )
            )
        }

        socketService.onError = { [weak self] text, description in
            self?.notificationModel?.showNotification(
                OrnamentNotification(
                    title: text,
                    message: description,
                    type: .error
                )
            )

            SentryService
                .sendMessage(
                    "Received error. Title: \(text) Description: \(description ?? "")"
                )
        }

        // MARK: Matching listeners

        socketService.onStartMatching = { [weak self] id, token in
            guard let self = self else { return }
        }

        socketService.onEnd = { [weak self] in
            guard let self = self else { return }
        }

        socketService.onGetPartnerInfo = { [weak self] payload in
            guard let self = self, self.shouldCall else { return }

            let roomInfo = RoomModel.decodeRoomInfo(from: payload)
            guard let roomInfo = roomInfo else { return }

            var shouldUpdate: Bool

            if self.partners.isEmpty {
                shouldUpdate = true
            } else {
                let currentIDs = Set(self.partners.map { $0.id })
                let newIDs = Set(roomInfo.partners.map { $0.id })
                shouldUpdate = currentIDs != newIDs
            }

            guard shouldUpdate else { return }

            self.roomId = roomInfo.roomId
            self.myInfo = roomInfo.myInfo
            self.partners = roomInfo.partners
            self.myLiveKitToken = roomInfo.myLiveKitToken

            if let friendIds = roomInfo.myInfo.friendIds, !friendIds.isEmpty {
                for friendId in friendIds {
                    if !self.friendsUsers.contains(friendId) {
                        self.friendsUsers.append(friendId)
                    }
                }
            }

            services.storageService.updateUserProfile(
                \.matchesCount,
                value: myInfo?.matchesCount
            )
        }

        socketService.onPartnerLeft = { [weak self] partnerId in
            guard let self = self, self.shouldCall else { return }

            self.partners.removeAll {
                $0.id == partnerId
            }

            if self.partners.isEmpty {
                self.reset()
            }
        }

        socketService.onPartnerJoinedVideo = { [weak self] userId in
            guard let self = self, !userId.isEmpty else { return }

            self.joinedVideoPartners.append(userId)
        }

        // MARK: Timer listeners

        socketService.onTimerUpdate = { [weak self] timerValue in
            self?.timerValue = timerValue
        }

        socketService.onTimerExtended = { time in
            self.hasExtendedTimer = true
        }

        socketService.onTimerEnded = { [weak self] in
            guard let self = self else { return }

            self.reset()
        }

        // MARK: Users Online listenrs

        socketService.onUserOnlineChanged = { [weak self] payload in
            guard let self = self,
                let userOnlineInfo = RoomModel.decodeUserOnlineInfo(
                    from: payload
                )
            else {
                return
            }

            self.updateUserStatus(userOnlineInfo)
        }

        // MARK: Connect Book listeners

        socketService.onConnectedUser = {
            [weak self] userId, cancel, isFriends in
            guard let self = self, !userId.isEmpty else { return }

            if cancel {
                self.partnersSentConnectUserRequest
                    .removeAll(where: { $0 == userId })
            } else {
                self.partnersSentConnectUserRequest.append(userId)

                if self.sentConnectUserRequests.contains(userId) {
                    let partner = self.partners
                        .first(where: { $0.id == userId })

                    if settingsViewModel?.audioSettings?.allSounds == true {
                        services.soundService.playSound(
                            named: "Friend-Accepted",
                            duration: 3
                        )
                    }

                    self.notificationModel?.showNotification(
                        OrnamentNotification(
                            title: "Partner has accepted your connection",
                            type: .success,
                            contentView: {
                                AnyView(
                                    AcceptedConnectionNotificationContentView(
                                        user: partner ?? nil
                                    )
                                )
                            }
                        )
                    )

                    NotificationCenter.default.post(
                        name: .didAddFriend,
                        object: nil,
                        userInfo: nil
                    )
                }
            }
        }

        socketService.onRemovedUser = { userId in
            guard !userId.isEmpty else { return }

            NotificationCenter.default.post(
                name: .didRemoveUser,
                object: nil,
                userInfo: ["userId": userId]
            )

            self.removeFriendLocal(userId: userId)
            //            self.removeInvitation(fromUserId: userId)
        }
    }
}

// MARK: Helpers
extension RoomModel {
    static func decodeRoomInfo(from dict: [String: Any])
        -> RoomResponseModel?
    {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(RoomResponseModel.self, from: data)
        } catch {
            SentryService.sendMessage("Failed to decode room: \(error)")
            return nil
        }
    }

    static func decodeUserOnlineInfo(from input: Any)
        -> [UserOnlineStatusModel]?
    {
        do {
            let data: Data
            if let dict = input as? [String: Any] {
                data = try JSONSerialization.data(withJSONObject: [dict])
            } else if let array = input as? [[String: Any]] {
                data = try JSONSerialization.data(withJSONObject: array)
            } else {
                SentryService
                    .sendMessage(
                        "Invalid input type",
                        context: SentryContext(extra: [
                            "func": "decodeUserOnlineInfo"
                        ])
                    )
                return nil
            }

            return try JSONDecoder().decode(
                [UserOnlineStatusModel].self,
                from: data
            )
        } catch {
            SentryService.sendMessage(
                "Failed to decode userOnline info: \(error)"
            )
            return nil
        }
    }

    static func decodeInvitationInfo(from input: Any) -> [InvitationModel]? {
        do {
            let data: Data
            if let dict = input as? [String: Any] {
                data = try JSONSerialization.data(withJSONObject: [dict])
            } else if let array = input as? [[String: Any]] {
                data = try JSONSerialization.data(withJSONObject: array)
            } else {
                SentryService.sendMessage(
                    "Invalid input type",
                    context: SentryContext(extra: [
                        "func": "decodeInvitationInfo"
                    ])
                )
                return nil
            }

            return try JSONDecoder().decode(
                [InvitationModel].self,
                from: data
            )
        } catch {
            SentryService.sendMessage(
                "Failed to decode invitations info: \(error)"
            )
            return nil
        }
    }

    static func decodeEventInfo(from input: Any) -> [EventModel]? {
        do {
            let data: Data
            if let dict = input as? [String: Any] {
                data = try JSONSerialization.data(withJSONObject: [dict])
            } else if let array = input as? [[String: Any]] {
                data = try JSONSerialization.data(withJSONObject: array)
            } else {
                SentryService.sendMessage(
                    "Invalid input type",
                    context: SentryContext(extra: [
                        "func": "decodeEventInfo"
                    ])
                )
                return nil
            }

            return try JSONDecoder().decode(
                [EventModel].self,
                from: data
            )
        } catch {
            SentryService.sendMessage("Failed to decode event info: \(error)")
            return nil
        }
    }

    static func decodeNotificationInfo(from dict: [String: Any])
        -> ShowNotificationModel?
    {
        do {
            let data = try JSONSerialization.data(withJSONObject: dict)
            return try JSONDecoder().decode(
                ShowNotificationModel.self,
                from: data
            )
        } catch {
            SentryService.sendMessage(
                "Failed to decode show notification info: \(error)"
            )
            return nil
        }
    }

    static func notifyChangeCallStatus(
        connected: Bool,
        isInviteCall: Bool? = false,
        isEventCall: Bool? = false,
    ) {
        //        NotificationCenter.default.post(
        //            name: .didChangeCallStatus,
        //            object: nil,
        //            userInfo: [
        //                "connected": connected,
        //                "isInviteCall": isInviteCall ?? false,
        //                "isEventCall": isEventCall ?? false,
        //            ]
        //        )

        NotificationCenter.default.post(
            name: .didChangeCallStatus,
            object: nil,
            userInfo: [
                "connected": connected,
                "isInviteCall": false,
                "isEventCall": false,
            ]
        )
    }
}
