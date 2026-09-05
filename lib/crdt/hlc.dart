/// Hybrid Logical Clock — combines real wall-clock time with a logical
/// counter, so clock drift or skew between devices can never cause a
/// wrong merge decision. Two HLCs are always totally ordered:
/// physical time is compared first, and the logical counter breaks
/// ties (including ties caused by clock skew putting two real edits
/// at the same millisecond).
class HLC {
  final int physicalTime; // milliseconds since epoch
  final int logicalCounter; // tie-breaker

  HLC(this.physicalTime, this.logicalCounter);

  /// Is this HLC "later" than [other]? Physical time decides first;
  /// the logical counter only matters when physical times are equal.
  bool isAfter(HLC other) {
    if (physicalTime != other.physicalTime) {
      return physicalTime > other.physicalTime;
    }
    return logicalCounter > other.logicalCounter;
  }

  /// Call this whenever you make a NEW local edit.
  ///
  /// If real time has moved forward since [last], reset the counter —
  /// physical time alone is enough to order this edit after the last
  /// one. If real time hasn't moved forward (clock hasn't ticked yet,
  /// or has even gone backward), keep the same physical time and bump
  /// the counter so this edit still sorts strictly after [last].
  static HLC tick(HLC? last) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (last == null || now > last.physicalTime) {
      return HLC(now, 0);
    }
    return HLC(last.physicalTime, last.logicalCounter + 1);
  }

  /// Call this whenever you RECEIVE an edit from another device.
  ///
  /// The resulting clock must be later than all three of: this
  /// device's own current time, the local HLC, and the remote HLC —
  /// that's what guarantees a received edit is never accidentally
  /// treated as older than something we already knew about.
  static HLC receive(HLC local, HLC remote) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int maxPhysical = [now, local.physicalTime, remote.physicalTime]
        .reduce((a, b) => a > b ? a : b);

    if (maxPhysical == local.physicalTime && maxPhysical == remote.physicalTime) {
      // Both clocks (and possibly "now") are tied on physical time —
      // take the higher counter and bump past it.
      final int higherCounter =
          local.logicalCounter > remote.logicalCounter
              ? local.logicalCounter
              : remote.logicalCounter;
      return HLC(maxPhysical, higherCounter + 1);
    } else if (maxPhysical == local.physicalTime) {
      return HLC(maxPhysical, local.logicalCounter + 1);
    } else if (maxPhysical == remote.physicalTime) {
      return HLC(maxPhysical, remote.logicalCounter + 1);
    }
    // "now" alone is strictly ahead of both — safe to reset the counter.
    return HLC(maxPhysical, 0);
  }

  @override
  String toString() => 'HLC($physicalTime, $logicalCounter)';

  @override
  bool operator ==(Object other) =>
      other is HLC &&
      other.physicalTime == physicalTime &&
      other.logicalCounter == logicalCounter;

  @override
  int get hashCode => Object.hash(physicalTime, logicalCounter);
}
