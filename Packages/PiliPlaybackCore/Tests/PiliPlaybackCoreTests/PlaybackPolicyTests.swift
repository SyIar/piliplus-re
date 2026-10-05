import Foundation
import Testing
@testable import PiliPlaybackCore

@Test func sleepDeadlineWinsOverEveryAutoplayMode() {
    for order in PlaybackOrder.allCases {
        #expect(PlaybackEndPolicy.resolve(order: order, currentIndex: 0, count: 3, sleepTimerStops: true) == .stop)
    }
}

@Test func repeatListWrapsButSequentialStops() {
    #expect(PlaybackEndPolicy.resolve(order: .repeatList, currentIndex: 2, count: 3, sleepTimerStops: false) == .advance(0))
    #expect(PlaybackEndPolicy.resolve(order: .sequential, currentIndex: 2, count: 3, sleepTimerStops: false) == .stop)
    #expect(PlaybackEndPolicy.resolve(order: .related, currentIndex: 2, count: 3, sleepTimerStops: false) == .loadRelated)
    #expect(PlaybackEndPolicy.resolve(order: .repeatList, currentIndex: nil, count: 0, sleepTimerStops: false) == .stop)
}

@Test func lateTimerCallbackCannotStartAnotherVideo() {
    var timer = SleepTimerPolicy()
    let deadline = Date(timeIntervalSince1970: 100)
    timer.schedule(deadline: deadline, finishCurrent: false)
    let shouldStop = timer.playbackEnded(now: deadline.addingTimeInterval(2))
    #expect(shouldStop)
    #expect(timer.preventsAutomaticPlayback)
}

@Test func finishCurrentWaitsOnlyAfterDeadline() {
    var timer = SleepTimerPolicy()
    let deadline = Date(timeIntervalSince1970: 100)
    timer.schedule(deadline: deadline, finishCurrent: true)
    let earlyEndStops = timer.playbackEnded(now: deadline.addingTimeInterval(-1))
    #expect(!earlyEndStops)
    let deadlineStops = timer.tick(now: deadline, hasActiveItem: true)
    #expect(!deadlineStops)
    #expect(timer.state == .waitingForEnd)
    let finalEndStops = timer.playbackEnded(now: deadline.addingTimeInterval(5))
    #expect(finalEndStops)
}

@Test func missingPlayerDoesNotDeferStopToAnUnrelatedFutureVideo() {
    var timer = SleepTimerPolicy()
    let deadline = Date(timeIntervalSince1970: 100)
    timer.schedule(deadline: deadline, finishCurrent: true)
    let shouldStop = timer.tick(now: deadline, hasActiveItem: false)
    #expect(shouldStop)
    timer.cancel()
    #expect(!timer.preventsAutomaticPlayback)
}

@Test func deadlineSurvivesPersistenceAndSuspension() throws {
    var original = SleepTimerPolicy()
    original.schedule(deadline: Date(timeIntervalSince1970: 100), finishCurrent: false)
    var restored = try JSONDecoder().decode(SleepTimerPolicy.self, from: JSONEncoder().encode(original))
    let shouldStop = restored.tick(now: Date(timeIntervalSince1970: 1000), hasActiveItem: true)
    #expect(shouldStop)
}

@Test func seekingInsideAdsAndOverlapsUsesOneDestination() {
    let ranges = [SkipSegment(id: "a", start: 10, end: 20), SkipSegment(id: "b", start: 18, end: 25)]
    #expect(SegmentSkipPolicy.destination(at: 15, segments: ranges) == 25)
    #expect(SegmentSkipPolicy.destination(at: 25, segments: ranges) == nil)
    #expect(SegmentSkipPolicy.destination(at: 2, segments: ranges) == nil)
    #expect(SegmentSkipPolicy.destination(at: .nan, segments: ranges) == nil)
}
