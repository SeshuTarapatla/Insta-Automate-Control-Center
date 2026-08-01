"""Read-only k8s access for the dependency panel. Deliberately thin: helm and pod
log streaming arrive in later phases, and guessing their shape now would be
speculation."""
import threading
from ast import literal_eval

from kubernetes import client, config

from ia_agent.logging import logger

_lock = threading.Lock()
_core: client.CoreV1Api | None = None
_version: client.VersionApi | None = None

NAMESPACE = "default"


def _clients() -> tuple[client.CoreV1Api, client.VersionApi]:
    """Loading kubeconfig costs tens of milliseconds and the panel polls, so the
    clients are built once. Not thread-safe by default, hence the lock."""
    global _core, _version
    with _lock:
        if _core is None or _version is None:
            config.load_kube_config()
            _core = client.CoreV1Api()
            _version = client.VersionApi()
        return _core, _version


def reset() -> None:
    """Drop the cached clients so the next call reloads kubeconfig — used when the
    cluster was unreachable, since a restarted k3s issues a new certificate."""
    global _core, _version
    with _lock:
        _core = _version = None


def server_version() -> str:
    _, version = _clients()
    info = version.get_code()
    return f"{info.git_version} ({info.platform})"


def _deployment_of(pod) -> str:
    """`insta-automate-5465cb5db5-f9dln` → `insta-automate`.

    A Deployment's pod is named `<deployment>-<pod-template-hash>-<suffix>`, so
    stripping the last two segments recovers the deployment exactly. Prefix matching
    would not do: `insta-automate` is a prefix of `insta-automate-worker`, and both
    of this chart's deployments also carry the *same* `app: insta-automate` label,
    so neither the name prefix nor the label can tell them apart on its own."""
    name = pod.metadata.name
    if (pod.metadata.labels or {}).get("pod-template-hash"):
        return name.rsplit("-", 2)[0]
    return name


def pods(deployment: str) -> list[dict]:
    """Every pod in the default namespace belonging to `deployment`."""
    core, _ = _clients()
    found = []
    for pod in core.list_namespaced_pod(NAMESPACE).items:
        if _deployment_of(pod) != deployment:
            continue
        statuses = pod.status.container_statuses or []
        found.append(
            {
                "name": pod.metadata.name,
                "phase": pod.status.phase,
                "ready": all(container.ready for container in statuses) if statuses else False,
                "restarts": sum(container.restart_count for container in statuses),
                "started_at": pod.status.start_time.isoformat() if pod.status.start_time else None,
            }
        )
    return found


def _decode_pod_log(raw: object) -> str:
    """The installed client sometimes hands back `str(bytes_response)` instead
    of a decoded string for this endpoint — i.e. the literal characters
    `b'...'` — rather than actual bytes or real text. Unwrap that case; pass
    everything else through untouched."""
    if isinstance(raw, bytes):
        return raw.decode("utf-8", errors="replace")
    if isinstance(raw, str) and (raw.startswith("b'") or raw.startswith('b"')):
        try:
            return literal_eval(raw).decode("utf-8", errors="replace")
        except (ValueError, SyntaxError):
            pass
    return raw  # type: ignore[return-value]


def pod_logs(deployment: str, since_seconds: int | None = None, tail_lines: int = 200) -> list[tuple[str, str]]:
    """New lines from one pod's container log, each as `(rfc3339_timestamp, text)`.

    `timestamps=True` prefixes every line with its own RFC3339 nanosecond
    timestamp, which is what lets the caller dedupe against a cursor (CP 4.1).
    The cursor here is `since_seconds` (relative), **not** `since_time`
    (absolute) — the installed `kubernetes` client's generated bindings for
    this endpoint never wired up `since_time` at all (`ApiTypeError:
    unexpected keyword argument`), a known gap in the generated client rather
    than a server limitation. The caller is expected to re-filter the
    (slightly overlapping) window this returns against its own last-seen
    timestamp, the same dedupe-at-the-boundary shape `run_logs` needs too.

    Only the first Running pod of the deployment is read — the scheduler runs
    as a single replica, and reading more would interleave two pods' lines
    with no way to tell them apart.

    A line the pod itself wrapped (Rich renders to the container's detected
    console width) still arrives as separate k8s log lines with no marker
    tying them back together — merged multi-line messages are a known gap,
    not attempted here."""
    core, _ = _clients()
    target = next((pod for pod in pods(deployment) if pod["phase"] == "Running"), None)
    if target is None:
        return []
    kwargs: dict = {"timestamps": True, "tail_lines": tail_lines}
    if since_seconds is not None:
        kwargs["since_seconds"] = max(1, since_seconds)
    raw = core.read_namespaced_pod_log(target["name"], NAMESPACE, **kwargs)
    text = _decode_pod_log(raw)
    lines = []
    for line in text.splitlines():
        ts, _, rest = line.partition(" ")
        if ts:
            lines.append((ts, rest))
    return lines


def secret(name: str) -> dict:
    from my_modules.kubernetes import Kubernetes

    try:
        return Kubernetes().get_secret(name)
    except Exception as error:
        logger.warning(f"could not read secret {name}: {error}")
        raise
