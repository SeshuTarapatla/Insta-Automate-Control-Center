import '../../core/service_models.dart';
import '../../ui/status.dart';

/// `ui/status.dart`'s `StatusDot` was generalised from `ServiceState` to
/// `StatusKind` (COMPONENTS.md §3) so it can serve anything with a
/// transient state, not just services — this is the small bridge back for
/// the two call sites that still think in `ServiceState`.
extension ServiceStateStatusKindX on ServiceState {
  StatusKind get statusKind => switch (this) {
    ServiceState.running => StatusKind.good,
    ServiceState.starting => StatusKind.info,
    ServiceState.backoff => StatusKind.warn,
    ServiceState.unhealthy => StatusKind.warn,
    ServiceState.failed => StatusKind.bad,
    ServiceState.stopped => StatusKind.neutral,
  };
}
