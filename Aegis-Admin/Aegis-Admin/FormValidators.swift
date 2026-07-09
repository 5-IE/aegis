import Foundation

/// Client-side mirrors of the backend zod schemas
/// (Aegis-Backend/src/routes/admin/users.ts, rooms.ts, beacons.ts, rollup.ts).
/// Validating here lets forms fail fast with a friendly inline message instead
/// of a backend 400.
enum FormValidators {
    // Limits copied from the backend zod schemas.
    static let usernameMaxLength = 50
    static let passwordMaxLength = 72
    static let emailMaxLength = 100
    static let nameMaxLength = 50
    static let roomNameMaxLength = 100
    static let beaconNameMaxLength = 100
    static let beaconIdentifierMaxLength = 100
    static let searchMaxLength = 100

    /// Pragmatic email shape check: one "@", a non-empty local part, and a
    /// domain with at least one dot. Matches what zod's `.email()` accepts
    /// for everyday addresses without rejecting valid ones over-eagerly.
    private static let emailPattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#

    // MARK: - Field validators (nil means valid)

    static func validateUsername(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter a username." }
        if value.count > usernameMaxLength {
            return "Username must be \(usernameMaxLength) characters or fewer."
        }
        return nil
    }

    static func validatePassword(_ value: String) -> String? {
        if value.isEmpty { return "Enter a password." }
        if value.count > passwordMaxLength {
            return "Password must be \(passwordMaxLength) characters or fewer."
        }
        return nil
    }

    static func validateEmail(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter an email address." }
        if value.count > emailMaxLength {
            return "Email must be \(emailMaxLength) characters or fewer."
        }
        if value.range(of: emailPattern, options: .regularExpression) == nil {
            return "Enter a valid email address."
        }
        return nil
    }

    static func validateOptionalName(_ raw: String, field: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count > nameMaxLength {
            return "\(field) must be \(nameMaxLength) characters or fewer."
        }
        return nil
    }

    static func validateRoomName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter a room name." }
        if value.count > roomNameMaxLength {
            return "Room name must be \(roomNameMaxLength) characters or fewer."
        }
        return nil
    }

    static func validateBeaconName(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter a beacon name." }
        if value.count > beaconNameMaxLength {
            return "Beacon name must be \(beaconNameMaxLength) characters or fewer."
        }
        return nil
    }

    static func validateBeaconIdentifier(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "Enter a beacon identifier." }
        if value.count > beaconIdentifierMaxLength {
            return "Beacon identifier must be \(beaconIdentifierMaxLength) characters or fewer."
        }
        return nil
    }

    /// Normalized beacon position: empty (means "no position") or a number
    /// in 0...1.
    static func validateOptionalPosition(_ raw: String, axis: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let parsed = Double(value), parsed >= 0, parsed <= 1 else {
            return "Position \(axis) must be a number between 0 and 1, or empty."
        }
        return nil
    }

    /// Positive integer or empty (empty means "not provided").
    static func validateOptionalUserID(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard let parsed = Int(value), parsed > 0 else {
            return "User ID must be a positive number."
        }
        return nil
    }

    // MARK: - Form validators (nil means valid)

    static func validate(userForm form: AdminUserForm) -> String? {
        if !form.isEditing, let message = validateUsername(form.username) {
            return message
        }
        if let message = validateEmail(form.email) {
            return message
        }
        if !form.isEditing, let message = validatePassword(form.password) {
            return message
        }
        if let message = validateOptionalName(form.firstName, field: "First name") {
            return message
        }
        if let message = validateOptionalName(form.lastName, field: "Last name") {
            return message
        }
        if form.role == .learner, form.session.isEmpty {
            return "Choose a session for the learner."
        }
        return nil
    }

    static func validate(roomForm form: AdminRoomForm) -> String? {
        validateRoomName(form.name)
    }

    static func validate(beaconForm form: AdminBeaconForm) -> String? {
        if let message = validateBeaconName(form.name) {
            return message
        }
        if let message = validateBeaconIdentifier(form.beaconIdentifier) {
            return message
        }
        if let message = validateOptionalPosition(form.positionXText, axis: "X") {
            return message
        }
        if let message = validateOptionalPosition(form.positionYText, axis: "Y") {
            return message
        }
        return nil
    }

    /// Trims and truncates a search term so it never exceeds the backend's
    /// 100-character limit (which would 400 the whole list request).
    static func sanitizedSearchTerm(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(searchMaxLength))
    }
}
