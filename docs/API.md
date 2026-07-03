A. User


1. Me (Profile)

GET /api/v1/me

RETURN { first_name }


2. Dashboard

GET /api/v1/dashboard

RETURN {
  total_attendance,
  total_late,
  leave_taken,
  today_status: enum ("Not Checked In", "Running Late", "Checked In", "Checked Out", "Not Checked Out", "Off")
}


3. Attendance History

GET /api/v1/histories

PARAM {
  month?,
  year?
}

RETURN {
  list {
    date,
    checked_in_at?,
    checked_out_at?,
    status: enum (Early, Late, Leave, Absent)
  }
}




B. Admin


1. Dashboard > Absence Summary (Today)

GET /api/v1/admin/absence-summary

RETURN {
  present_summary: {
    on_time: int,
    late_clock_in: int
  },
  absent_summary: {
    absent: int,
    no_clock_in: int
  }
}


2. Dashboard > Overview (Today)

GET /api/v1/admin/overview

PARAM {
  name?
}

RETURN {
  list {
    name,
    session,
    clocked_in_at,
    clocked_out_at,
    status
  }
}


3. Live Radar > General

GET /api/v1/admin/rooms

RETURN {
  list of RoomResource
}


4. Live Radar > Live Map

GET /api/v1/admin/rooms/:room_id/map

RETURN {
  list of LogResource on that time
}


5. Live Radar > Current Occupants

GET /api/v1/admin/rooms/:room_id/current-occupants

RETURN {
  list {
    user {
      name,
      session
    },
    duration,
    status
  }
}


6. Live Radar > Additional Data

GET /api/v1/admin/rooms/:room_id/additional-data

RETURN {
  room_temperature,
  humidity,
  people_in_room
}