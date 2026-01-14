import Combine
@preconcurrency import LiveKit
import SwiftUI

class GlobalMatchingViewModel: NotifiableWrapper, MatchingTypeViewModel {
    @Injected private var services: Services

    var onStateChange: ((ConnectionState) -> Void)?

    private(set) var room: Room?
    private(set) var roomModel: RoomModel?

    override init() {
        super.init()
    }

    func attachRoom(_ room: Room) {
        self.room = room
    }

    func bindSocket(_ roomModel: RoomModel) {
        self.roomModel = roomModel
    }

    private func propagateState(_ newState: ConnectionState) {
        onStateChange?(newState)
    }
}

extension GlobalMatchingViewModel {
    func startMatching() {
        roomModel?.globalManager?.startMatch()
    }

    func skip(completion: SocketAckCompletion? = nil) {
        DispatchQueue.main.async {
            Task {
                self.roomModel?.globalManager?.skip(completion: completion)
                await self.room?.disconnect()

                if self.notificationModel?.notification?.contentView != nil {
                    self.notificationModel?.dismissNotification()
                }
            }
        }
    }

    func endCall(
        state: ConnectionState,
        notifyChangeCallStatus: Bool? = true
    ) {
        guard self.roomModel?.shouldCall == true else { return }

        DispatchQueue.main.async {
            Task {
                self.roomModel?.endCall()
                await self.room?.disconnect()

                self.propagateState(state)
            }
        }
    }
}
