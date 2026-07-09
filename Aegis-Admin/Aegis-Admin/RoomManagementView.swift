import SwiftUI

struct RoomManagementView: View {
    @ObservedObject var viewModel: AdministrationViewModel
    @Binding var roomForm: AdminRoomForm?
    @Binding var roomDeleteTarget: Room?

    var body: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {
                RoomManagementToolbar {
                    roomForm = AdminRoomForm()
                }

                AdaptiveHorizontalTable(
                    minWidth: 720,
                    rowCount: viewModel.rooms.count,
                    state: viewModel.roomState
                ) {
                    AdminRoomsTable(
                        rows: viewModel.rooms,
                        state: viewModel.roomState,
                        beaconCount: { viewModel.beaconCount(for: $0) },
                        beaconStatus: { viewModel.beaconStatus(for: $0) },
                        edit: { roomForm = AdminRoomForm(room: $0) },
                        delete: { roomDeleteTarget = $0 }
                    )
                }

                AdminPaginationFooter(
                    summary: "Showing \(viewModel.rooms.count) rooms",
                    message: viewModel.roomActionMessage,
                    successWords: ["Room"],
                    canGoPrevious: false,
                    canGoNext: false,
                    previous: {},
                    next: {}
                )
            }
        }
    }
}
