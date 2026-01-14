final class SocketIOService {
    static let shared = SocketIOService()

    private var manager: SocketManager?
    private var socket: SocketIOClient?

    private var storedUserId: String?
    private var storedToken: String?

    // MARK: Callbacks

    var onSocketConnected: (() -> Void)?
    var onSocketDisconnected: (() -> Void)?
    var onStartMatching: ((_ userId: String, _ token: String?) -> Void)?
    var onRoomCreated: ((_ roomId: String, _ users: [String]) -> Void)?
    var onGetPartnerInfo: ((_ partnerPayload: [String: Any]) -> Void)?
    var onEnd: (() -> Void)?
    var onPartnerJoinedVideo: ((_ userId: String) -> Void)?
    var onPartnerLeft: ((_ partnerId: String) -> Void)?
    var onTimerUpdate: ((_ timerValue: Int) -> Void)?
    var onTimerExtended: ((_ time: Int) -> Void)?
    var onTimerEnded: (() -> Void)?
    var onConnectedUser:
        ((_ userId: String, _ cancel: Bool, _ isFriends: Bool) -> Void)?
    var onRemovedUser: ((_ userId: String) -> Void)?
    var onUserOnlineChanged: ((_ payload: [String: Any]) -> Void)?
    var onInvitedToMeet: ((_ invitation: [String: Any]) -> Void)?
    var onCancelledInvite: ((_ fromUserId: String) -> Void)?
    var onPartnerJoinedInviteMeet:
        ((_ from: String, _ inviteId: String) -> Void)?
    var onNotifiedEvent: ((_ payload: [String: Any], _ time: Int) -> Void)?
    var onNewEventCreated: ((_ payload: [String: Any]) -> Void)?
    var onEventRemoved: ((_ eventId: String) -> Void)?
    var onShowNotification: ((_ payload: [String: Any]) -> Void)?
    var onError: ((_ text: String, _ description: String?) -> Void)?

    private init() {}

    var isSocketConnected: Bool {
        socket?.status == .connected
    }

    func initSocket(userId: String, token: String) {
        guard socket == nil else { return }
        storedUserId = userId
        storedToken = token
        createSocket()
        socket?.connect()
    }

    func disconnectAndDestroy() {
        socket?.disconnect()
        cleanupSocket()
    }

    private func cleanupSocket() {
        socket?.off(clientEvent: .connect)
        socket?.off(clientEvent: .disconnect)
        socket?.removeAllHandlers()
        socket?.disconnect()
        socket = nil
        manager = nil
    }
}

extension SocketIOService {
    // MARK: Matching
    func connect(userId: String, token: String) {
        guard let sock = socket else { return }
        switch sock.status {
        case .connected:
            emitStartMatching()
        case .connecting:
            return
        case .disconnected:
            cleanupSocket()
        default:
            cleanupSocket()
        }
    }

    private func emitStartMatching() {
        guard let uid = storedUserId, let tok = storedToken else { return }

        socket?.emit(
            SocketEvent.startMatching.rawValue,
            ["id": uid, "token": tok]
        )
    }

    func sendSkipCall(completion: SocketAckCompletion?) {
        socket?
            .emitWithAck(
                SocketEvent.skipCall.rawValue
            )
            .timingOut(after: 5) { response in
                self.handleSocketAckResponse(response, completion: completion)
            }
    }

    func sendEnd() {
        socket?.emit(SocketEvent.end.rawValue)
    }

    func changeShouldCall(shouldCall: Bool) {
        socket?.emit(
            SocketEvent.changeShouldCall.rawValue,
            ["shouldCall": shouldCall]
        )
    }

    func joinedVideo(roomId: String, meetTime: Int) {
        guard !roomId.isEmpty else { return }

        socket?.emit(
            SocketEvent.joinedVideo.rawValue,
            ["roomId": roomId, "meetTime": meetTime]
        )
    }

    // MARK: Timer

    func extendTimer(to roomId: String, seconds: Int) {
        guard !roomId.isEmpty else { return }

        socket?
            .emit(
                SocketEvent.extendTimer.rawValue,
                ["roomId": roomId, "seconds": seconds]
            )
    }

    // MARK: Users Online

    func changeUserOnline(
        isOnline: Bool,
        isBusy: Bool,
        completion: ((_ response: Any) -> Void)?
    ) {
        guard let userId = self.storedUserId, let userToken = self.storedToken
        else { return }

        guard let sock = socket else { return }
        switch sock.status {
        case .connected:
            socket?
                .emitWithAck(
                    SocketEvent.changeUserOnline.rawValue,
                    [
                        "id": userId,
                        "token": userToken,
                        "isOnline": isOnline,
                        "isBusy": isBusy,
                    ],
                )
                .timingOut(after: 5) { response in
                    if let dict = response.first as? [String: Any],
                        let usersOnline = dict["usersOnline"]
                    {
                        completion?(usersOnline)
                    }
                }
        case .connecting:
            return
        case .disconnected:
            cleanupSocket()
        default:
            cleanupSocket()
        }
    }

    // MARK: Connect Book

    func connectUserRequest(
        userId: String,
        completion: SocketAckCompletion?
    ) {
        guard !userId.isEmpty else { return }

        socket?
            .emitWithAck(
                SocketEvent.connectUserRequest.rawValue,
                ["to": userId]
            )
            .timingOut(after: 5) { response in
                self.handleSocketAckResponse(response, completion: completion)
            }
    }

    func cancelConnectUserRequest(
        userId: String,
        completion: SocketAckCompletion?
    ) {
        guard !userId.isEmpty else { return }

        socket?
            .emitWithAck(
                SocketEvent.cancelConnectUserRequest.rawValue,
                ["to": userId]
            )
            .timingOut(after: 5) { response in
                self.handleSocketAckResponse(response, completion: completion)
            }
    }

    func removeUserRequest(
        userId: String,
        completion: SocketAckCompletion?
    ) {
        guard !userId.isEmpty else { return }

        socket?
            .emitWithAck(
                SocketEvent.removeUserRequest.rawValue,
                ["to": userId],
            )
            .timingOut(after: 5) { response in
                self.handleSocketAckResponse(response, completion: completion)
            }
    }

    // MARK: Setup Socket

    private func createSocket() {
        guard socket == nil else { return }

        let urlString = "\(AppSettings.nodeScheme)://\(AppSettings.nodeHost)"
        guard let url = URL(string: urlString) else { return }

        manager = SocketManager(
            socketURL: url,
            config: [
                .log(false),
                .compress,
                .path("/bridge"),
                .reconnectAttempts(-1),
                .reconnectWait(1),
                .reconnectWaitMax(5),
            ]
        )
        socket = manager?.defaultSocket

        // MARK: Listeners

        socket?.on(clientEvent: .connect) { [weak self] _, _ in
            self?.onSocketConnected?()
        }

        socket?.on(clientEvent: .disconnect) { [weak self] _, _ in
            self?.onSocketDisconnected?()
        }

        socket?.on(SocketEvent.showNotification.rawValue) {
            [weak self] data, _ in
            guard let dict = data.first as? [String: Any]
            else { return }

            self?.onShowNotification?(dict)
        }

        socket?.on(SocketEvent.error.rawValue) { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
                let text = dict["text"] as? String
            {
                let description = dict["description"] as? String ?? ""

                self?.onError?(text, description)
            } else if let text = data.first as? String {
                self?.onError?(text, nil)
            } else {
                self?.onError?("Error", nil)
            }
        }

        // MARK: Matching listeners

        socket?.on(SocketEvent.roomCreated.rawValue) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                let roomId = dict["roomId"] as? String,
                let users = dict["users"] as? [String]
            else { return }

            self?.onRoomCreated?(roomId, users)
        }

        socket?.on(SocketEvent.getPartnerInfo.rawValue) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                let payload = dict["data"] as? [String: Any]
            else { return }

            self?.onGetPartnerInfo?(payload)
        }

        socket?.on(SocketEvent.partnerLeft.rawValue) { [weak self] data, _ in
            guard let dict = data.first as? [String: Any],
                let partnerId = dict["partnerId"] as? String
            else { return }

            self?.onPartnerLeft?(partnerId)
        }

        socket?.on(SocketEvent.partnerJoinedVideo.rawValue) {
            [weak self] data, _ in

            if let dict = data.first as? [String: Any],
                let userId: String = dict["userId"] as? String
            {
                self?.onPartnerJoinedVideo?(userId)
            }
        }

        socket?.on(SocketEvent.end.rawValue) { [weak self] _, _ in
            self?.onEnd?()
        }

        // MARK: Timer listeners

        socket?.on(SocketEvent.timerUpdate.rawValue) { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
                let timerValue = dict["timerValue"] as? Int
            {
                self?.onTimerUpdate?(timerValue)
            }
        }

        socket?.on(SocketEvent.timerExtended.rawValue) { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
                let time = dict["timerValue"] as? Int
            {
                self?.onTimerExtended?(time)
            }
        }

        socket?.on(SocketEvent.timerEnded.rawValue) { [weak self] _, _ in
            self?.onTimerEnded?()
        }

        // MARK: Users Online listeners

        socket?.on(SocketEvent.userOnlineChanged.rawValue) {
            [weak self] data, _ in

            if let dict = data.first as? [String: Any] {
                self?.onUserOnlineChanged?(dict)
            }
        }

        // MARK: Connect Book listeners

        socket?.on(SocketEvent.connectedUser.rawValue) { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
                let userId: String = dict["from"] as? String
            {
                let cancel: Bool = dict["cancel"] as? Bool ?? false
                let isFriends: Bool = dict["isFriends"] as? Bool ?? false

                self?.onConnectedUser?(userId, cancel, isFriends)
            }
        }

        socket?.on(SocketEvent.removedUser.rawValue) { [weak self] data, _ in
            if let dict = data.first as? [String: Any],
                let userId: String = dict["from"] as? String
            {
                self?.onRemovedUser?(userId)
            }
        }
    }
}

extension SocketIOService {
    private func handleSocketAckResponse(
        _ response: [Any],
        completion: SocketAckCompletion?
    ) {
        guard let completion = completion else { return }

        guard response.first as? String != "NO ACK" else {
            print("NO ACK")

            return
        }

        guard let dict = response.first as? [String: Any] else {
            completion(nil, nil)
            return
        }

        let completionStatus = dict["completionStatus"]
        let data = dict["data"]

        completion(completionStatus, data)
    }
}
