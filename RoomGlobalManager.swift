import Combine
import SwiftUI

final class RoomGlobalManager: ObservableObject {
    private weak var roomModel: RoomModel?
    let socketService = SocketIOService.shared
    private let userId: String
    private let token: String

    init(roomModel: RoomModel, userId: String, token: String) {
        self.roomModel = roomModel
        self.userId = userId
        self.token = token
    }

    // MARK: - Matching Methods

    func startMatch() {
        guard !(roomModel?.shouldCall ?? true) else { return }

        roomModel?.changeShouldCall(true)
        socketService.connect(userId: userId, token: token)
    }

    func restartMatch() {
        socketService.connect(userId: userId, token: token)
    }

    func skip(completion: SocketAckCompletion? = nil) {
        socketService.sendSkipCall(completion: completion)
        roomModel?.reset()
    }
}
