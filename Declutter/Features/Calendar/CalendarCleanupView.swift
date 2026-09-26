import SwiftUI

/// Past, one-off calendar events older than a chosen age, grouped by month, with multi-select.
/// Deleting goes through the review screen.
struct CalendarCleanupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var reviewPlan: CleanupPlan?

    private var calendar: CalendarCleanupModel { model.calendar }

    var body: some View {
        content
            .navigationTitle("Calendar cleanup")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if calendar.access == .full {
                    ToolbarItem(placement: .topBarTrailing) { ageMenu }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if calendar.access == .full && !calendar.events.isEmpty {
                    SelectionBar(count: calendar.selection.count, singular: "event", plural: "events") {
                        reviewPlan = model.makeCalendarPlan()
                    }
                }
            }
            .sheet(item: $reviewPlan) { ReviewView(plan: $0) }
            .task { if calendar.state == .idle { await calendar.load() } }
            .onChange(of: scenePhase) { _, phase in
                // Access may have changed in Settings.
                if phase == .active { Task { await calendar.load() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch calendar.access {
        case .notDetermined:
            EmptyStateView(
                systemImage: "calendar",
                title: "Allow calendar access",
                message: "Declutter lists past events you may no longer need, so you can clear them out. Your calendar stays on this iPhone and nothing is deleted without your approval.",
                actionTitle: "Allow calendar access"
            ) {
                Task { await calendar.requestAccess() }
            }
        case .writeOnly:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "Full calendar access needed",
                message: "Declutter can add events but not see them. To list old events, choose Full Access for Declutter in Settings › Calendars.",
                actionTitle: "Open Settings"
            ) {
                SystemSettings.open()
            }
        case .denied:
            EmptyStateView(
                systemImage: "calendar.badge.exclamationmark",
                title: "Calendar access is off",
                message: "Turn on Calendar access in Settings so Declutter can list old events on this iPhone.",
                actionTitle: "Open Settings"
            ) {
                SystemSettings.open()
            }
        case .full:
            if calendar.state != .loaded {
                LoadingView(text: "Finding old events…")
            } else if calendar.events.isEmpty {
                EmptyStateView(
                    systemImage: "calendar.badge.checkmark",
                    title: "No old events",
                    message: "Nothing \(calendar.age.title.lowercased()) to clear. Repeating events and calendars you can't change aren't listed."
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        let events = calendar.events
        return ScrollView {
            ScreenSummary(
                text: "\(counted(events.count, "event")) \(calendar.age.title.lowercased())",
                detail: "Oldest first. Repeating events and calendars you can't change, like Holidays and Birthdays, aren't listed."
            )
            .padding(.top, Theme.gap)

            BulkActionBar {
                let allSelected = events.allSatisfy { calendar.selection.contains($0.id) }
                BulkActionButton(
                    title: allSelected ? "Deselect all" : "Select all",
                    count: events.count,
                    systemImage: allSelected ? "circle" : "checkmark.circle"
                ) {
                    calendar.selection = allSelected ? [] : Set(events.map(\.id))
                }
            }
            .padding(.vertical, Theme.gap)

            LazyVStack(alignment: .leading, spacing: Theme.spacing, pinnedViews: .sectionHeaders) {
                ForEach(months(events), id: \.title) { month in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(month.events) { event in
                                EventRow(event: event, isSelected: calendar.selection.contains(event.id))
                                    .onTapGesture {
                                        Haptics.select()
                                        calendar.toggle(event.id)
                                    }
                                if event.id != month.events.last?.id {
                                    Theme.hairline.frame(height: 1).padding(.leading, 30)
                                }
                            }
                        }
                        .padding(.horizontal, Theme.spacing)
                        .surface()
                    } header: {
                        Text(month.title)
                            .font(.heading(.headline))
                            .foregroundStyle(Theme.pine)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                            .background(Theme.mist)
                    }
                }
            }
            .padding(.horizontal, Theme.page)
            .padding(.bottom, Theme.spacing)
        }
        .screenBackground()
    }

    private var ageMenu: some View {
        Menu {
            Picker(selection: Binding(get: { calendar.age }, set: { calendar.age = $0 })) {
                ForEach(EventAge.allCases) { Text($0.title).tag($0) }
            } label: {
                Label("Show events", systemImage: "clock")
            }
            .pickerStyle(.inline)
        } label: {
            Label("How old", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("calendar.age")
    }

    private func months(_ events: [EventSummary]) -> [(title: String, events: [EventSummary])] {
        var result: [(title: String, events: [EventSummary])] = []
        for event in events {
            let title = event.start.formatted(.dateTime.month(.wide).year())
            if result.last?.title == title {
                result[result.count - 1].events.append(event)
            } else {
                result.append((title, [event]))
            }
        }
        return result
    }
}

struct EventRow: View {
    let event: EventSummary
    var isSelected: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(event.tint)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.pine)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if let isSelected {
                SelectionCheckmark(isSelected: isSelected)
            }
        }
        .padding(.vertical, 12)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
        .accessibilityIdentifier("eventRow")
    }

    private var detail: String {
        let date = event.isAllDay
            ? event.start.formatted(date: .abbreviated, time: .omitted)
            : event.start.formatted(date: .abbreviated, time: .shortened)
        return event.calendarTitle.isEmpty ? date : "\(date) · \(event.calendarTitle)"
    }
}
