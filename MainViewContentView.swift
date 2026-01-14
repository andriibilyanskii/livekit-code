import SwiftUI

struct MainViewContentView: View {
    @Injected var services: Services

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var roomModel: RoomModel

    private var tabTitle: String
    private var tabImage: String
    private var tag: Int

    init(
        tabTitle: String,
        tabImage: String,
        tag: Int
    ) {
        self.tabTitle = tabTitle
        self.tabImage = tabImage
        self.tag = tag
    }

    init() {
        self.tabTitle = ""
        self.tabImage = ""
        self.tag = 0
    }

    init(
        tag: Int
    ) {
        self.tabTitle = ""
        self.tabImage = ""
        self.tag = tag
    }

    var body: some View {
        if services.authenticationService.isAuthenticated {
            self.contentView
        } else {
            self.contentView
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            #if os(visionOS)
                HStack(spacing: 0) {
                    leftContainerView
                    contentContainerView
                }
            #else
                VStack(spacing: 0) {
                    leftContainerView
                    contentContainerView
                }
            #endif
        }
        .tabItem {
            Label(tabTitle, systemImage: tabImage)
        }
        .tag(tag)
    }
}

extension MainViewContentView {
    private func getTitle(tag: Int) -> String {
        switch tag {
        case 1:
            return "Connect Book"
        case 2:
            return "Meet Now"
        case 3:
            return "Edit Profile"
        case 4:
            return "App Settings"
        case 5:
            return "Create Profile"
        case 6:
            return ""
        case 7:
            return "Mixer Events"
        default:
            return ""
        }
    }

    private func getView(tag: Int) -> some View {
        switch tag {
        case 1:
            return AnyView(ContentWrapper { ConnectBookContentView() })
        case 2:
            return AnyView(ContentWrapper { MatchingContentView() })
        case 3:
            return AnyView(ContentWrapper { ProfileContentView() })
        case 4:
            return AnyView(ContentWrapper { SettingsContentView() })
        case 5:
            return AnyView(ContentWrapper { ProfileContentView() })
        case 6:
            return AnyView(AuthLobbyContentView())
        case 7:
            return AnyView(ContentWrapper { MixerEventsContentView() })
        default:
            return AnyView(EmptyView())
        }
    }

    private var showUsersOnline: Bool {
        switch tag {
        case 2:
            return true
        default:
            return false
        }
    }
}

extension MainViewContentView {
    private var leftContainerView: some View {
        Group {
            if self.tag != 6 {
                VStack(alignment: .leading, spacing: 0) {
                    LeftContentHeader(
                        title: getTitle(tag: self.tag),
                        showUsersOnline: self.showUsersOnline
                    )

                    MainLeftView(tag: self.tag)
                }
                #if os(visionOS)
                    .padding(.vertical, 28)
                    .padding(.horizontal, 24)
                    .frame(width: 430)
                #endif
            }
        }
    }

    private var contentContainerView: some View {
        getView(tag: self.tag)
    }
}


struct MatchingView: View {
    var body: some View {
        MainViewContentView(
            tabTitle: "Meet Now",
            tabImage: "person.2.fill",
            tag: 2
        )
    }
}
