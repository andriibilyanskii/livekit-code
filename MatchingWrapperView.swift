import AVFoundation
import Combine
@preconcurrency import LiveKit
import LiveKitComponents
import SwiftUI
import os

struct MatchingWrapperView<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    @EnvironmentObject private var matchingViewModel: MatchingViewModel
    @EnvironmentObject private var roomModel: RoomModel
    @EnvironmentObject private var eventsViewModel: EventsViewModel
    @EnvironmentObject private var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var notificationModel: OrnamentNotificationModel
    @EnvironmentObject private var room: Room
    @EnvironmentObject private var soundService: SoundService

    @Environment(\.selection) private var selection

    @State private var isConnecting = false
    @State private var connectTask: Task<Void, Never>? = nil

    let logger = Logger(subsystem: "persona.vision", category: "LiveKit")

    var body: some View {
        content()
            .onAppear {
                self.handleConnectionStateChange(
                    from: nil,
                    to: matchingViewModel.connectionState
                )
            }
            .onChange(of: room.connectionState) {
                oldState,
                newState in

                guard roomModel.shouldCall else {
                    return
                }

                switch newState {

                case .disconnected:
                    // here check selection status to start new matching or end it
                    if matchingViewModel.connectionState == .disconnecting {

                        if selection != 2 {
                            matchingViewModel
                                .changeConnectionState(
                                    .disconnected,
                                    connectionType: nil
                                )

                            roomModel.changeShouldCall(false)

                            return
                        } else {
                            matchingViewModel.changeConnectionState(.searching)
                        }
                    }

                    roomModel.globalManager?.restartMatch()

                    break

                case .connected:
                    // if partners are empty skip call to prevent show empty partner info
                    if roomModel.partners.isEmpty {
                        matchingViewModel.changeConnectionState(.disconnecting)

                        self.notificationModel.showNotification(
                            OrnamentNotification(
                                title: "Failed to receive partner info",
                                type: .error,
                                customDuration: 5
                            )
                        )
                    }

                case .disconnecting:
                    break

                default:
                    break
                }
            }
            .onChange(of: roomModel.partners.count) {
                self.handleChangeRoomIdOrPartners()
            }
            .onChange(of: matchingViewModel.connectionState) {
                oldState,
                newState in
                self.handleConnectionStateChange(
                    from: oldState,
                    to: newState
                )
            }
            .onChange(of: selection) { oldSelection, newSelection in
                if oldSelection == 2, newSelection != 2 {
                    if matchingViewModel.connectionState == .searching {
                        matchingViewModel.endCall(state: .disconnected)
                    } else if matchingViewModel.connectionState.isNotConnected {
                        //                        roomModel.resetIsWaitingEvent()
                    }
                }
            }
    }
}

extension MatchingWrapperView {
    // MARK: Functions

    func connectRoom(token: String) {
        guard room.connectionState == .disconnected else {
            return
        }

        Task {
            do {
                try await room.connect(
                    url: wsURL,
                    token: token,
                    connectOptions: ConnectOptions(enableMicrophone: true)
                )
            } catch {
                await MainActor.run {
                    logger.error("LiveKit connect failed: \(error)")

                    SentryService.captureError(
                        error,
                        context: SentryContext(
                            extra: [
                                "description":
                                    "LiveKit connect failed: \(error)",
                                "userId": roomModel.myId,
                            ]
                        )
                    )

                    notificationModel.showNotification(
                        OrnamentNotification(
                            title: "Unfortunately that didn't work",
                            message: "Let's try this again...",
                            type: .warning
                        )
                    )
                }
                return
            }

            await enableCamera()

            matchingViewModel.emitHasConnectedToLiveKit()
        }
    }

    private func enableCamera(
        maxRetries: Int = 10,
        delaySeconds: Double = 0.5
    ) async {
        #if !targetEnvironment(simulator)
            do {
                try await room.localParticipant.setCamera(enabled: true)
                print("Camera enabled successfully")
                return
            } catch {
                sendCameraRetryMessage(error: error)
            }

            handleErrorFunc(
                NSError(
                    domain: "CameraRetry",
                    code: 999,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Camera could not be enabled after retries. (This is custom error)"
                    ]
                )
            )
        #endif
    }

    private func sendCameraRetryMessage(error: Error, attempt: Int = 0) {
        SentryService.sendMessage(
            "Failed to enable camera (attempt \(attempt)): \(error)",
            context: SentryContext(
                extra: [
                    "userId": roomModel.myId,
                    "partnerId": roomModel.partners.first?.id ?? "",
                    "roomId": roomModel.roomId,
                ]
            )
        )
    }

    private func handleErrorFunc(_ error: Error) {
        logger.error("Failed to connect to LiveKit: \(error)")

        SentryService.sendMessage(
            "Failed to connect to LiveKit media: \(error)",
            context: makeSentryContext()
        )

        notificationModel.showNotification(
            OrnamentNotification(
                title: "Failed to connect to LiveKit media",
                type: .error,
                customDuration: 10
            )
        )
    }

    private func notifyStateNotDisconnected() {
        notificationModel.showNotification(
            OrnamentNotification(
                title: "LiveKit connection state is not \"Disconnected\"",
                message: "Will try to reconnect",
                type: .warning
            )
        )

        SentryService.sendMessage(
            "LiveKit connection state is not \"Disconnected\"",
            context: makeSentryContext()
        )
    }

    private func makeSentryContext() -> SentryContext {
        SentryContext(extra: [
            "userId": roomModel.myId,
            "roomId": roomModel.roomId,
            "user": roomModel.myInfo,
            "partner": roomModel.partners.first,
        ])
    }

    // Prevents potential recursion stack growth
    private func reattemptConnect(token: String) {
        Task { [self] in
            self.connectRoom(token: token)
        }
    }

    private func handleConnectionStateChange(
        from oldState: ConnectionState?,
        to newState: ConnectionState
    ) {
        guard oldState != newState else { return }

        print(
            "Connection state changed: \(String(describing: oldState)) → \(newState)"
        )

        if newState == .searching {
            matchingViewModel.startMatching()

            if settingsViewModel.audioSettings?.waitingSound == true {
                soundService.playAudio(
                    name: "music_for_waiting_with_delay",
                    type: "mp3",
                    volume: 0.5
                )
            }
        } else if oldState == .searching && newState == .disconnected {
            matchingViewModel.endCall(state: .disconnected)
            soundService.stopAudio()
        } else {
            soundService.stopAudio()
        }
    }

    @MainActor
    func handleChangeRoomIdOrPartners() {
        guard matchingViewModel.connectionState != .disconnected
        else { return }

        let hasRoomId = !roomModel.roomId.isEmpty
        let hasPartner = !roomModel.partners.isEmpty
        let isDisconnectedRoom = room.connectionState == .disconnected
        let isConnected = matchingViewModel.connectionState == .connected
        let isDisconnecting =
            matchingViewModel.connectionState == .disconnecting

        if hasRoomId, hasPartner, isDisconnectedRoom, !isConnected {
            self.connectToLiveKit()

            return
        }

        if isDisconnecting || isDisconnectedRoom {
            return
        }

        matchingViewModel.changeConnectionState(.disconnecting)

        Task {
            await room.disconnect()
        }

        if self.notificationModel.notification?.contentView != nil {
            self.notificationModel.dismissNotification()
        }
    }

    func connectToLiveKit() {
        matchingViewModel.changeConnectionState(.connecting)

        let roomId = self.roomModel.roomId
        let token = self.roomModel.myLiveKitToken

        guard !roomId.isEmpty, !token.isEmpty else {
            self.notificationModel.showNotification(
                OrnamentNotification(
                    title: "Failed to receive room id or LiveKit token",
                    type: .error,
                    customDuration: 5
                )
            )

            matchingViewModel.changeConnectionState(.searching)

            SentryService
                .sendMessage(
                    "Failed to receive room id or LiveKit token",
                    context: SentryContext(extra: ["userId": roomModel.myId])
                )

            return
        }

        connectRoom(token: token)
    }
}
