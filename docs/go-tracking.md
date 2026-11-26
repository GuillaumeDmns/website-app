# How GO follows a journey

GO follows a journey option step by step (walks, waits, rides) from three sources: the device's **position fixes**,
the **clock** (the journey's times, shifted by the delays measured), and the **real-time departures** of the rides.
This document explains how they are combined, case by case, with every threshold the code uses. Keep it in sync with
the code: each section names the functions it describes.

Guiding principles:

1. **A precise GPS fix outranks everything.** Above ground, the GPS knows where the user is; the clock only guesses.
2. **Being somewhere is not moving.** Someone standing still on a platform (or seated in a train waiting there) is
   waiting, whatever their distance to the stop's point. Only movement along the line says a vehicle left.
3. **The clock fills the gaps, and only them.** Underground, indoors or with the location off, the clock leads, but it
   starts from the last thing the GPS measured, never goes further than a vehicle can, and can be corrected afterwards.
4. **What was guessed can be undone; what was seen cannot.** A step reached by the clock can be moved back by a precise
   fix; a step seen by the GPS or said by the user is never moved back by the clock.
5. **Never ask, never show a doubt.** The vehicle the user is on is worked out silently; the journey just follows it.

Code map:

| File | Role |
|---|---|
| `lib/features/go/go_tracker.dart` | `GoTracker`: pure state machine, `update(progress, input)` → new progress and alerts |
| `lib/features/go/go_vehicle_match.dart` | `VehicleMatch`: which departure the user is on, by scores |
| `lib/features/go/go_controller.dart` | `GoController`: feeds fixes, clock and departures, follows the vehicle matched, location on/off |
| `lib/features/go/go_trace.dart` | `GoTrace`: session traces (dev and beta builds) |
| `lib/core/location/position_feed.dart` | `PositionFeed`: the device's fixes and location service status |
| `test/support/go_replay.dart` | `replayGoTrace`: plays an exported trace again in a test |

---

## 1. The model

### Steps and phases

`GoTracker.steps` are the journey's sections except waits: **moves** (walk, bike, transfer…) and **rides** (transit).
`GoProgress` says where the user is:

| Field | Meaning |
|---|---|
| `step`, `phase` | current step; `moving` (a move), `waiting` (at a ride's stop), `onBoard`, `arrived` |
| `along` | meters done along the step's path (what the map fades) |
| `stopIndex` | on board: last stop the vehicle has left (0 = boarding stop) |
| `stopFloor` | on board: last stop the **GPS** saw left; the clock never goes below it |
| `shift` | how late the user is on the schedule from the current ride on (delay measured); GO's own: it moves the clock, the dot and the alerts, never a time shown (the ride card, the header's arrival, the notification and the connections show the API's times of the vehicle followed; its time past and the user not there yet, "À l'approche") |
| `preciseAlong`, `preciseAt` | last precise fix on the ride (waiting: where the user stands/sits on the platform) |
| `departedAt` | when the vehicle taken left the boarding stop |
| `byClock` | the current step/phase was reached by the clock or an assumption, not seen |
| `hintStop`, `pendingHintStop` | underground: last station taken from a rough position, and one waiting for confirmation |
| `issue` | `offRoute`, `missed`, `cancelled` |
| `joined` | on a move: the user was seen on its path (within 80 m) |

### Fixes: four kinds

Every fix from the device goes through `GoController._onFix`, then `GoTracker.update`.

| Kind | Rule | What it may say |
|---|---|---|
| **Precise (P)** | accuracy ≤ 30 m and fresh (position first given ≤ 30 s ago) | anything: where the user is, still or moving |
| **Rough (R)** | 30 m < accuracy ≤ 100 m, fresh | a move's progress; on board, only to hold back the clock's "get off" |
| **Hint** | not precise, accuracy ≤ 300 m, fresh, within accuracy + 150 m of a station of the ride | underground: "about at that station now" |
| **Stale** | position given again (see below), or older than 30 s | nothing |

"First given" is `positionSince`: the system often hands the **same position again with a new timestamp** (the last
one before going underground). Such a fix keeps the time it was first given, so it turns stale after 30 s. Waiting and
on board, a rough fix within the accuracies of the previous rough one counts as the same position too (a cell tower, a
GPS stuck at a station while the metro goes five stations further).

No usable fix for 60 s (`_noFixDelay`) → **the schedule leads** (`followsSchedule`, "Pas de GPS" in the card).

How often fixes are asked (`goLocationNeed`): every 1 s on foot/by bike on screen, 2 s off screen, 5 s waiting, 3 s on
board, none once arrived.

### Speed

`sureSpeed(fix)` = reported speed minus its accuracy (a phone lying indoors reports 2.5 ± 2.1 m/s: that is 0.4 m/s
sure). **Moving** in a vehicle = sure speed ≥ 4 m/s (`_movingSpeed`).

---

## 2. Moves (walking, cycling)

`GoTracker._move`, each fix:

- **Progress**: the fix projected on the path from `along − 30 m` on; `along` never goes back.
- **Joined**: a fix within 80 m of the path.
- **Off the way**: `distance − accuracy > 150 m` for 1 min → `offRoute` (alert `offroute-<step>`), said with
  "Recalculer" / "Ignorer": the journey is only ever recalculated on the user's tap (`GoController.recalculate`), never on
  its own (a train's wrong position once had GO swap the plan for a metro the user never meant to take). Not before the path was joined while
  within 400 m of where it starts (out of a train, the platform is hundreds of meters from where the walk is drawn from).
  Back within 80 m clears it.
- **Done**: within 40 m of the path's end (or of the step's end point). The journey's **last** move ends only right by
  the destination (`_atDestination`): a fix ≤ 25 m accurate within 25 m of it or of the walk's end; or within 60 m once
  the arrival time is 2 min past (big places, indoors).
- **Already riding the next vehicle**: if the next step is a ride and the fix is seen riding it (`_riding`, see §3; "far"
  only when off the walk, > 60 m from it), the move is done.
- **Hurry**: the next ride leaves before the user can walk the rest at 1.2 m/s plus a minute → alert `hurry-<step>`.
- **No fix for 60 s**: done at the step's arrival time + `shift`; the next step is then `byClock`.

---

## 3. Waiting and boarding

### The platform zone

`GoStep.platformZone` is a stretch of the ride's line around the boarding stop:

```
        stop's point
            |
  ----[-150 m]=====+==========================[+L]------------>  direction of the ride
        from                                    to
```

| Mode | L (vehicle length) |
|---|---|
| RER, Transilien, TER | 450 m (a double train; a terminus' point is at the head of its platform) |
| Metro | 150 m |
| Tram | 80 m |
| Bus and others | 40 m |

A fix is **in the zone** when its projection on the line is between `from` and `to` and within 100 m + accuracy of it.

### Boarding (`GoTracker._wait`)

| Situation | Result |
|---|---|
| P, still, in the zone (on the platform or seated in the vehicle waiting there) | **waiting**; its place `preciseAlong` kept (the seat) |
| P (or R), moving ≥ 4 m/s, within 60 m of the line, > 80 m along it | **on board**; left when the vehicle started from the seat: `now − (along − seat) / speed` (within 500 m of it) |
| Any fix, within 100 m of the line, > 150 m from the stop's point, and beyond `max(400 m, zone end + 200 m)` | **on board** whatever the speed (a train held at a signal, back from a tunnel); left by the ride's times (`scheduledTo`) |
| P, the departure 90 s past (3 min if only scheduled), still (< 2 m/s) in the zone or within 150 m of the stop | **missed** (`missed-<step>`), unless the real time says the vehicle is at the stop (`Departure.atStop`) |
| P, the departure 90 s past, elsewhere and not riding | on board at the expected departure (`byClock`) |
| No fix / only rough ones, the departure 60 s past | on board at the expected departure (`byClock`): underground, rough positions stay at the station while the metro leaves |

`_departureTaken`: if the time measured is within a minute of the expected departure (real time, else planned), the
expected one is kept (more precise); otherwise the user took another vehicle (a late one, an earlier one) and the time
measured is kept. `shift` = departure taken − planned (clamped to −30 min … +60 min). The departure taken is never
before the last precise fix still on the platform (`preciseAt`): seen on board only far down the line, the schedule's
time made the late direct of 9:16 at Bécon the stopping train of 9:14, gone while the user still stood there.

Also while waiting: `delay-<step>` when the vehicle is ≥ 3 min late, `soon-<step>` within 2 min, `cancel-<step>`,
platform announcements and changes for trains (`platform-<step>-<platform>`).

**A missed or cancelled vehicle** is replaced at once by the line's next departure (`_replaceMissed`,
`replacementRide`), shown as retained in the departures card, which offers another one or a recalculation.

**The departure aimed at** is reworked until the user boards (`GoController._retarget`, `targetRide`,
`readyAtRide`), after every progress and every departures refresh, for every ride ahead: when the user can be at its
stop = the moves before it at the user's pace (the current one from the meters left, minus 150 m for a train or metro
stop, whose point is mid-platform), the rides before it at their API arrival. The aim is the first departure catchable
with 30 s to spare arriving earliest (never one arriving later than another catchable one); the current one is kept
while it can still be caught (60 s) unless another arrives a minute earlier. A new aim must hold 20 s before it is
taken (no flicker standing still); it is then chosen like a tap in the departures card (`choose`), without a word: the
cards show the new train's API times. A departure the user chose in a card (`choose(byUser: true)`) is kept while it can be caught
(60 s), whatever arrives first; chosen while waiting, it is the one `VehicleMatch` aims at (`follow`), not the one
aimed at when the wait began: left with another train, the journey follows that one. While a ride waits, the vehicle followed's API times are taken up as they move
(`_followTimes`, ≥ 30 s): only API times are shown for transport, GO's `shift` never rewrites them.

### Why this matters (the incident of November 2026)

Seated early in a late train at a terminus, 420 m down the platform: the old rule ("400 m along → on board whatever
the speed") boarded at once, dated the departure "now", guessed the train leaving on time then, and got the user off at
that train's arrival. Now: still in the zone → waiting; the train moves → on board at its real departure.

---

## 4. Which vehicle (`VehicleMatch`)

Created as soon as the user waits for a ride, fed with every departure seen at the stop (`GoController._seen`, the
departed ones kept with their last real time). After boarding, the ride's departures are followed **5 more minutes**
(`_watchBoarded`, same provider key: no extra request), so a late train's real time and `atStop` keep coming.

Never asks the user: the most likely departure is shown as if sure. No departure is privileged beyond the one the
journey aims at, which starts with **+1** (two trains 30 s apart with the same stops are told apart by nothing else).
A departure is known by what it is (`sameVehicleDeparture`): its train number, else its mission, else its scheduled
time, else a real time within 60 s; never by its stops.

Each departure is a candidate with a score starting at 0. Each thing seen lowers scores **once per event**, not per fix
(fixes a second apart say the same thing). **Strong** signs don't depend on how the vehicle runs; **weak** ones do (a
slowdown, a stop at a signal, a rough GPS):

| Evidence | Kind | When | Penalty |
|---|---|---|---|
| **Gone without the user** | strong | P, still, in the zone for ≥ 30 s at t: a departure that left before t − 60 s (and the real time didn't say it was still at the stop afterwards) | −8 |
| **Not yet left** | strong | a candidate leaving > 60 s after a fix saw the user away from the stop | −8 |
| **Time left, measured** | strong | the user seen leaving (not `byClock`): a candidate leaving > 90 s from that time | −8 |
| **Time left** | weak | at boarding (`departed`), the others, by their gap to the time left | −min(4, (gap / 30 s)² / 2) |
| **Where it should be** | weak | on board, a P fix, at most once a minute: expected position by its real departure and stop times vs the GPS | −min(4, (Δ / (500 m + 10 % of the way))² / 2); a sign only when the user is **ahead** of it (a slowing train is behind its times, never ahead) |
| **Station stopped at** | weak | a station where the candidates' stops differ: still (< 1 m/s and < 1.5 m/s along) 15 s within 200 m of it | −3 for those not stopping there (a signal, maybe) |
| **Station run through** | strong | crossed never under 5 m/s, fixes ≤ 15 s apart | −8 for those stopping there |
| **Still at the stop** | strong | the real time says a candidate is at the stop while the user is already beyond the zone | −8 |

A weak sign counts from 1 point. Candidates at boarding: departures whose stops are known (≥ 2), not cancelled,
leaving between the last time the user was seen on the platform and the first time seen away, ±3 min (only around
the time assumed without the GPS). The departure aimed at (found by what it is, else the one leaving closest to the
ride's time, within 60 s) is followed at first; following none, one scoring ≥ −2. **Another one is followed** when it
scores **2 points** better and has fewer strong signs, or at least two weak signs fewer, than the one followed: a rough
GPS gives few signs and leaves the one aimed at, a slowing train never makes it another one. **Locked**: once one leads
every other by 8 points, each of them with a strong sign against it, it is the one until the alighting stop.
Switching retimes the journey on it (`_followRide`, `retimeJourney`: its stops, its arrival, the connections after
it) and keeps the progress (`onAnotherVehicle`).

Fixes worse than 50 m or further than 100 m from the line tell nothing about stations.

---

## 5. On board (`GoTracker._ride`)

### With the GPS (above ground)

A **P fix within 100 m of the line**:

- `along` = its projection (searched from `preciseAlong − 100 m`), `preciseAlong`/`preciseAt` updated.
- **Stops**: the last stop left = the last one ≥ 30 m behind it; `stopFloor` raised to it. While a P fix came within
  the last **60 s**, only the GPS moves `stopIndex` (it may even move it back from where the clock had put it).
- **Get off**: within 40 m before the alighting stop, or within 60 m of the section's end.
- **Delay measured** (`_recalibrated`), from the second P fix on board on: moving → `shift` toward
  `time − scheduled time at that point`; standing → at least that (minus 20 s of dwell at a station), since it hasn't
  left. At most 30 s change per fix: a few fixes converge, one odd fix can't jump.

A **P fix more than 300 m + accuracy from the line for 1 min** → `offRoute` (wrong train or direction, off too early):
the ride card shows "Recalculer" / "Ignorer", recalculated only on the user's tap.

### Without it (underground, rough fixes, location off)

When no P fix came for 60 s:

- **Clock**: stop k is left at its time + `shift` + 20 s dwell; the arrival at its time + `shift`.
- **Reach**: never further than `preciseAlong + top speed × time since preciseAt` (40 m/s trains, 22 m/s metro,
  15 m/s others), so a train seen in a station at 8:02 can't be "5 stations further" at 8:03.
- **Floor**: never before `stopFloor` (a stop the GPS saw left).
- **Rough fix behind**: a fresh R fix on the line more than accuracy + 500 m before the alighting stop holds back the
  clock's "get off".
- **Hints** (`_hint`): a hint at station k at time t:
  - ignored if k is the boarding stop or not after the last hint taken (`hintStop`): each station once, never backward
    (a position the system keeps giving while the metro goes on);
  - ignored if k is more than 1 station ahead of where the clock is;
  - more than 2 stations **behind** the clock: kept pending; taken only if a second hint at a station further on
    confirms it (the vehicle really is that late), otherwise it was the GPS stuck behind;
  - taken: if t is within [clock's arrival at k − 60 s, + 20 s dwell + 60 s] nothing changes; otherwise `shift` is set
    so that the vehicle stands at k at t, halfway through its stop.

Example, metro 2 min late: a hint near S2 at 8:06:10 (planned 8:04) → `shift` ≈ +2 min → "get off" at 8:14, not 8:12.

### Alerts

- `prepare-<step>`: once the stop before the alighting one is left and the arrival is within 4 min (without the stops:
  2 min before it).
- `alight-<step>`: arrived (urgent, rings off screen).

### Back on board (`_backOnBoard`)

If the user was got off **by the clock** (`byClock`) and the next move's path isn't joined yet, a P fix within 50 m of
the ride's line puts them back on board when it is more than 500 m before the alighting stop, or moving ≥ 4 m/s more
than 40 m before it. `stopIndex` from the GPS, the `alight` alert re-armed.

---

## 6. Location off, back on, and relocation

### Off

`PositionFeed.serviceEnabled` (Geolocator's service status) or a `LocationServiceDisabledException` on the fixes →
`GoState.locationOff`: the last fix is forgotten, the schedule leads (with the delay measured so far), and the card going
on shows "Localisation désactivée · suivi d'après l'horaire" with **Activer** (`fixLocationIssue`). The foreground
service and alerts go on.

### Back on (`_reacquired`)

The device's stream is opened again (`PositionFeed.reopen`: Android's stream ends with the location). Then:

- fixes older than the moment it came back, and the last position from before it went off, are ignored;
- a P fix is taken at once; rough ones need **two agreeing** (distinct, within their accuracies of each other);
- the fix taken is **placed anywhere on the journey** (`GoInput.relocate` → `_relocate`).

### Relocation (`_relocate`)

| Situation | Result |
|---|---|
| The fix is on the current step's path (≤ 100 m + accuracy) | nothing moves |
| On a later step's path (several steps ahead allowed) | that step; the one closest to where the clock is (`_clockStep`) when several qualify |
| On the step before, the current one reached `byClock` | back to it (the only way back) |
| Ride: still and within the zone + 200 m | waiting for it |
| Ride: moving or further | on board, stops from its position |
| Move | on it, at its position |
| Nowhere: further than 300 m + accuracy from every step | `offRoute` (recalculated only on the user's tap) |

Relocation also runs after a **restart** (the session restored, its last fix not kept) and after **3 min without a precise fix**
(a long tunnel).

---

## 7. Cases at a glance

| Case | What GO does |
|---|---|
| Seated in a late train at a terminus, 400 m down the platform | waiting; on board when it moves; that train followed (others gone without the user are ruled out) |
| Another train of the line leaves on time meanwhile | ruled out (gone while the user was still at the platform) |
| Train held at a signal just after leaving | on board once beyond the zone + 200 m, or moving |
| Direct and stopping trains leaving 30 s apart | the time can't tell; the first station where they differ does (stopped / ran through) |
| Two trains with the same stops, minutes apart | time left, then position vs real time once a minute; the train followed is the one of its number (SNCF), else of its stops within 2 min of its time: another one is never that one early (the line L's 21:41 taken while the 21:50 was followed) |
| Rough positions as the train leaves, on board seen only far down the line | the departure taken is not before the last precise fix on the platform: the late direct followed, not the stopping train gone before it (Bécon, 9:16 for 9:11) |
| Planned vehicle late, real time says "à quai" | never missed |
| Vehicle only scheduled, not seen | given up 3 min after its time (90 s with real time) |
| Metro, GPS stuck at the entrance | stale → clock from the departure, `shift` from the last measure |
| Metro, positions near some stations | hints set the clock; one behind ignored unless confirmed |
| RER: outdoors, tunnel, outdoors | delay measured outdoors, clock in the tunnel from it, GPS leads again at the exit |
| Clock says "get off" but the train is late and the GPS sees it on the line | back on board |
| Wrong train / wrong direction | off the line for 1 min → off the way, "Recalculer" offered |
| Location off for several steps | clock; when back, placed where the fix is, possibly steps ahead |
| App killed and restarted mid-journey | session restored, next fix relocated |

---

## 8. Debugging a real journey

Development and **beta** builds (beta = production backend, installable next to the store app: the one to take on a
real trip) keep a trace of the last 3 GO sessions (`GoTrace`): the journey, every fix as the device gave it, the
departures received per ride, location on/off, progress changes, vehicles followed, departures chosen (`choose`,
`byUser` for a tap in a card), and what the user says: `flag` ("GO se trompe", the flag button beside the GPS figures,
the moment marked with an optional note) and `taken` (once arrived, the arrival card asks for each ride boarded which
departure was really taken, among those seen at its stop within 8 min of the user leaving,
`GoController.takenOptions`; one tap, written into the session even after it ended). Never asked in the published app,
never during the journey. Stored on the device only (`LocalStore` key `go_traces`), written when the app leaves the
screen, at the end of the session, every 600 events and at once for what the user says.

Export: GO's page, the share button beside the GPS figures ("Exporter la trace").

**The traces folder.** Exports go into `traces/` at the root of the app, kept out of git by `.git/info/exclude` (the
developer's own trips: never published, not even the folder's name). `test/features/go/go_traces_test.dart` plays
every session found there again (each once, its longest copy across exports; skipped without the folder, as in the
CI), the user's taps included, and checks it: played to its end, the departure aimed at never swapping back and forth
before boarding on its own, the end reached when the trace reached it, and on board each ride the departure the user
took (`taken` events, else `traces/expected.json`, written by hand: per session a `note`, `taken` per ride step by
train number or local time, and `taps` for traces older than the `choose` events). Run it before committing a change
to GO:

```bash
flutter test test/features/go/go_traces_test.dart
```

It prints per session when the user was on board each ride and which departure GO followed. A single session in a
test of its own:

```dart
final session = (jsonDecode(File('traces/my_trip.json').readAsStringSync()) as List).last as Map<String, Object?>;
final replayed = await replayGoTrace(session, taps: {/* untraced taps, by time */});
// replayed: (at, state) after each fix / departures / service event, on a simulated clock (goClockProvider)
```

The trace's own `progress` and `follow` events show what the app decided at the time, to compare with the replay
after a fix.
