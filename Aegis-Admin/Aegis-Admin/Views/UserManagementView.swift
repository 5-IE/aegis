import SwiftUI

struct UserManagementView: View {
    @ObservedObject var viewModel: AdministrationViewModel
    @ObservedObject var sessionStore: SessionStore
    @Binding var userForm: AdminUserForm?

    var body: some View {
        WhitePanel {
            VStack(alignment: .leading, spacing: 16) {
                AdministrationToolbar(
                    searchText: $viewModel.searchText,
                    applyFilters: {
                        Task { await viewModel.applyFilters(sessionStore: sessionStore) }
                    },
                    addUser: {
                        userForm = AdminUserForm()
                    }
                )

                AdaptiveHorizontalTable(
                    minWidth: 760,
                    rowCount: viewModel.users.count,
                    state: viewModel.state
                ) {
                    AdminUsersTable(
                        rows: viewModel.users,
                        state: viewModel.state,
                        edit: { userForm = AdminUserForm(user: $0) }
                    )
                }

                AdminPaginationFooter(
                    summary: viewModel.pageSummary,
                    message: viewModel.actionMessage,
                    successWords: ["User", "Password"],
                    canGoPrevious: viewModel.canGoPrevious,
                    canGoNext: viewModel.canGoNext,
                    previous: {
                        Task { await viewModel.previousPage(sessionStore: sessionStore) }
                    },
                    next: {
                        Task { await viewModel.nextPage(sessionStore: sessionStore) }
                    }
                )
            }
        }
    }
}
