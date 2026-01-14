import Combine
@preconcurrency import LiveKit
import LiveKitComponents
import SwiftUI

let wsURL = "wss://*****.livekit.cloud"

enum ConnectionState {
    case searching  // when on waiting room, but play
    case connecting  // when receive roomID
    case connected  // users LiveKit connection started
    case disconnecting  // user has pressed exit/skip
    case disconnected  // when no lobby

    var isNotConnected: Bool {
        switch self {
        case .disconnecting,
            .searching,
            .disconnected:
            return true
        default:
            return false
        }
    }
}

enum ConnectionType {
    case global
    case invites
    case events
}

class MatchingViewModel: NotifiableWrapper, ObservableObject {
    @Injected private var services: Services

    @Published private(set) var connectionType: ConnectionType? = nil
    @Published private(set) var connectionState: ConnectionState = .disconnected

    private var globalMatchingViewModel: GlobalMatchingViewModel?
    //    private var invitesMatchingViewModel: InvitesMatchingViewModel?
    //    private var eventsMatchingViewModel: EventsMatchingViewModel?

    private var currentMatchingViewModel: (any MatchingTypeViewModel)? {
        switch connectionType {
        case .global:
            return globalMatchingViewModel
        //        case .invites:
        //            return invitesMatchingViewModel
        //        case .events:
        //            return eventsMatchingViewModel
        default:
            return nil
        }
    }

    override init() {
        super.init()
        setupViewModels()
    }

    private(set) var room: Room?
    private(set) var roomModel: RoomModel?

    private func setupViewModels() {
        globalMatchingViewModel = GlobalMatchingViewModel()
        //        invitesMatchingViewModel = InvitesMatchingViewModel()
        //        eventsMatchingViewModel = EventsMatchingViewModel()

        setupStateObservers()
    }

    private func setupStateObservers() {
        globalMatchingViewModel?.onStateChange = { [weak self] state in
            self?.handleChildStateChange(.global, state: state)
        }

        //        invitesMatchingViewModel?.onStateChange = { [weak self] state in
        //            self?.handleChildStateChange(.invites, state: state)
        //        }
        //
        //        eventsMatchingViewModel?.onStateChange = { [weak self] state in
        //            self?.handleChildStateChange(.events, state: state)
        //        }
    }

    func attachRoom(_ room: Room) {
        self.room = room
        globalMatchingViewModel?.attachRoom(room)
        //        invitesMatchingViewModel?.attachRoom(room)
        //        eventsMatchingViewModel?.attachRoom(room)
    }

    func bindSocket(_ roomModel: RoomModel) {
        self.roomModel = roomModel
        globalMatchingViewModel?.bindSocket(roomModel)
        //        invitesMatchingViewModel?.bindSocket(roomModel)
        //        eventsMatchingViewModel?.bindSocket(roomModel)
    }

    override func setNotificationModel(_ model: OrnamentNotificationModel) {
        super.setNotificationModel(model)

        globalMatchingViewModel?.setNotificationModel(model)
        //        invitesMatchingViewModel?.setNotificationModel(model)
        //        eventsMatchingViewModel?.setNotificationModel(model)
    }

    func changeConnectionType(_ newType: ConnectionType) {
        guard newType != self.connectionType else { return }

        if connectionState != .disconnected {
            endCall(state: .disconnected, notifyChangeCallStatus: false)
        }

        self.connectionType = newType
        self.connectionState = .disconnected
    }

    func changeConnectionState(
        _ newState: ConnectionState,
        connectionType: ConnectionType? = nil
    ) {
        guard newState != self.connectionState else { return }

        print(
            "MatchingViewModel - connection state: old \(self.connectionState) new \(newState)"
        )

        if let connectionType = connectionType {
            self.connectionType = connectionType
        }

        self.connectionState = newState
    }

    private func handleChildStateChange(
        _ type: ConnectionType,
        state: ConnectionState
    ) {
        if self.connectionType == nil {
            self.connectionType = type
        }

        guard self.connectionType == type else { return }

        self.connectionState = state
    }
}

extension MatchingViewModel {
    public func startMatching() {
        currentMatchingViewModel?.startMatching()
    }

    public func skipOrEndCall() {
        //        if self.roomModel?.isCallByInvite == true {
        //            self.endCall(state: .disconnected, notifyChangeCallStatus: true)
        //        } else {
        self.skip()
        //        }
    }

    public func skip(completion: SocketAckCompletion? = nil) {
        currentMatchingViewModel?.skip(completion: completion)
    }

    public func endCall(
        state: ConnectionState,
        notifyChangeCallStatus: Bool? = true
    ) {
        if let currentVM = currentMatchingViewModel {
            currentVM.endCall(
                state: state,
                notifyChangeCallStatus: notifyChangeCallStatus
            )
        } else {
            print("end call - no current VM, executing directly")
            DispatchQueue.main.async {
                Task {
                    self.roomModel?.endCall()
                    await self.room?.disconnect()
                    self.changeConnectionState(state)
                }
            }
        }
    }

    func emitHasConnectedToLiveKit() {
        self.changeConnectionState(.connected)
        roomModel?.joinedVideo()
    }
}

protocol MatchingTypeViewModel: ObservableObject {
    var onStateChange: ((ConnectionState) -> Void)? { get set }

    func startMatching()
    func skip(completion: SocketAckCompletion?)
    func endCall(state: ConnectionState, notifyChangeCallStatus: Bool?)
}
