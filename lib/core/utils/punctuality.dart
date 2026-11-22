/// How far off its schedule the real time must put a departure for it to show late or early: 2 min. Closer, the offset
/// is mostly noise, not a delay felt on the platform: a feed's steady offset from the GTFS schedule (the RER A at Gare de
/// Lyon, every train +45 s, even those of midnight) or a few seconds across a minute; Citymapper shows those on time
/// too. Only for what is shown: GO's tracking and the vehicle matching keep the exact offset.
const shownOffset = Duration(minutes: 2);

/// Whether a time [off] its schedule (expected less planned) shows late: from [shownOffset], or as soon as it is later
/// at all when the real time says it is [delayed] (some bus operators do, from a minute; SNCF and RATP never do).
bool showsLate(Duration off, {bool delayed = false}) => off >= shownOffset || (delayed && off > Duration.zero);

/// Whether a time [off] its schedule shows early: from [shownOffset] ahead (the real time has no early status)
bool showsEarly(Duration off) => off <= -shownOffset;
