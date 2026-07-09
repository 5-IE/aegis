import SwiftUI

struct BeaconManagementView: View {
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore

    @Binding var beaconForm: AdminBeaconForm?
    @Binding var beaconDeleteTarget: AdminBeacon?

    var body: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {

                BeaconManagementToolbar(
                    searchText: $viewModel.beaconSearchText,
                    assignmentFilter: $viewModel.beaconAssignmentFilter,
                    roomFilterID: $viewModel.beaconRoomFilterID,
                    rooms: viewModel.rooms,
                    applyFilters: {
                        Task {
                            await viewModel.applyBeaconFilters(sessionStore: sessionStore)
                        }
                    },
                    addBeacon: {
                        beaconForm = AdminBeaconForm()
                    }
                )

                AdaptiveHorizontalTable(
                    minWidth: 820,
                    rowCount: viewModel.filteredBeacons.count,
                    state: viewModel.beaconState
                ) {
                    AdminBeaconsTable(
                        rows: viewModel.filteredBeacons,
                        state: viewModel.beaconState,
                        edit: { beacon in
                            beaconForm = AdminBeaconForm(beacon: beacon)
                        },
                        delete: { beacon in
                            beaconDeleteTarget = beacon
                        }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.beaconPageSummary,
                    message: viewModel.beaconActionMessage,
                    successWords: ["Beacon"],
                    canGoPrevious: viewModel.canGoPreviousBeaconPage,
                    canGoNext: viewModel.canGoNextBeaconPage,
                    previous: {
                        Task {
                            await viewModel.previousBeaconPage(sessionStore: sessionStore)
                        }
                    },
                    next: {
                        Task {
                            await viewModel.nextBeaconPage(sessionStore: sessionStore)
                        }
                    }
                )
            }
        }
    }
}
