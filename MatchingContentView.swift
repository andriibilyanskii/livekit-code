import Combine
@preconcurrency import LiveKit
import LiveKitComponents
import SDWebImageSwiftUI
import SwiftUI

struct MatchingContentView: View {
    @EnvironmentObject private var matchingViewModel: MatchingViewModel
    @EnvironmentObject private var roomModel: RoomModel
    @EnvironmentObject private var room: Room

    @Environment(\.isFocused) var isFocused: Bool

    @State private var partnerCountryName: String = ""

    var body: some View {
        Group {
            GeometryReader { geometry in
                VStack(spacing: 16) {
                    if matchingViewModel.connectionState.isNotConnected {
                        self.searchingStateView(geometry: geometry)
                    } else {
                        #if os(visionOS)
                            self.connectedStateView(geometry: geometry)
                        #else
                            ScrollView(.horizontal) {
                                ScrollView {
                                    self.connectedStateView(geometry: geometry)
                                }
                            }
                        #endif
                    }
                }
        }
    }
}

extension MatchingContentView {
    //MARK: UI Views

    private func searchingStateView(geometry: GeometryProxy) -> some View {
        WaitingRoomView(geometry: geometry)
    }

    private func connectedStateView(geometry: GeometryProxy) -> some View {
        Group {
            #if os(visionOS)
                HStack(spacing: 15) {
                    ParticipantsList(geometry: geometry)
                    ParticipantInfoView()
                }
            #else
                ScrollView {
                    VStack(spacing: 15) {
                        ParticipantsList(geometry: geometry)
                        ParticipantInfoView()
                    }
                    .background(.gray.opacity(0.5))
                }
            #endif
        }
        .padding()
    }
}

extension MatchingContentView {
    // MARK: - Helpers

    static func videoWidth(
        for geometry: GeometryProxy,
        width: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        #if os(visionOS)
            return width
        #else
            return min(geometry.size.width * 0.7, height)
        #endif
    }

    static func videoHeight(
        for geometry: GeometryProxy,
        width: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        #if os(visionOS)
            return height
        #else
            return videoWidth(for: geometry, width: width, height: height)
                * (height / width)
        #endif
    }
}
