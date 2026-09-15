"""
Request-scoped middleware: correlation ids, access logging, and rate limiting.
"""

from __future__ import annotations

import logging
import time
from collections import defaultdict, deque
from threading import Lock

from fastapi import Request, status
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import AUTH_RATE_LIMIT, RATE_LIMIT_ENABLED
from app.logging_config import new_request_id, request_id_var

logger = logging.getLogger("app.access")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """
    Give every request an id, log its outcome, and echo the id back.

    A client that hits an error can quote ``X-Request-ID`` and we can find the
    exact log line, rather than guessing from a timestamp.
    """

    async def dispatch(self, request: Request, call_next):
        incoming = request.headers.get("X-Request-ID")
        request_id = incoming or new_request_id()
        token = request_id_var.set(request_id)

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            # The exception handlers turn this into a response; just record the
            # timing before it propagates.
            elapsed_ms = (time.perf_counter() - started) * 1000
            logger.exception(
                "%s %s failed after %.1fms",
                request.method,
                request.url.path,
                elapsed_ms,
            )
            raise
        finally:
            request_id_var.reset(token)

        elapsed_ms = (time.perf_counter() - started) * 1000
        response.headers["X-Request-ID"] = request_id

        # Health checks fire constantly; logging them buries everything else.
        if request.url.path != "/health":
            logger.info(
                "%s %s -> %s (%.1fms)",
                request.method,
                request.url.path,
                response.status_code,
                elapsed_ms,
                extra={
                    "extra_fields": {
                        "method": request.method,
                        "path": request.url.path,
                        "status": response.status_code,
                        "duration_ms": round(elapsed_ms, 1),
                    }
                },
            )
        return response


def _parse_limit(spec: str) -> tuple[int, int]:
    """Turn "10/minute" into (10, 60)."""
    units = {"second": 1, "minute": 60, "hour": 3600, "day": 86400}
    try:
        count, _, unit = spec.partition("/")
        return int(count), units[unit.strip().lower()]
    except (ValueError, KeyError):
        # Bad config shouldn't disable protection — fall back to a sane limit.
        logger.warning("Unparseable AUTH_RATE_LIMIT %r; using 10/minute", spec)
        return 10, 60


class AuthRateLimitMiddleware(BaseHTTPMiddleware):
    """
    Throttle *failed* attempts on the unauthenticated auth endpoints.

    These were an unlimited password-guessing oracle: no lockout, no attempt
    counter, nothing.

    Only failures count against the budget. Counting every call would punish
    legitimate use: a family shares one public IP behind home NAT, so four
    people opening the app at once — each doing a login and a token refresh —
    would burn a whole-IP allowance and lock the household out. Brute force
    needs thousands of *wrong* guesses, so budgeting failures targets the
    attack without touching normal traffic.

    In-process state, so it resets on deploy and is per-instance. Fine for a
    family-sized deployment; a multi-instance setup wants Redis instead.
    """

    #: Only the endpoints that accept credentials from anonymous callers.
    PROTECTED_SUFFIXES = ("/auth/login", "/auth/register", "/auth/refresh")

    #: Responses that count as a failed attempt. 422 is a malformed body,
    #: which is what a careless scripted attack produces.
    FAILURE_STATUSES = frozenset({400, 401, 403, 409, 422})

    def __init__(self, app):
        super().__init__(app)
        self._max_requests, self._window_seconds = _parse_limit(AUTH_RATE_LIMIT)
        self._hits: dict[str, deque[float]] = defaultdict(deque)
        self._lock = Lock()

    def _client_key(self, request: Request) -> str:
        # Behind a PaaS load balancer the real client is in X-Forwarded-For.
        forwarded = request.headers.get("X-Forwarded-For")
        if forwarded:
            return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "unknown"

    def _recent_failures(self, key: str) -> int:
        """Failures inside the current window, pruning anything older."""
        cutoff = time.monotonic() - self._window_seconds
        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] < cutoff:
                hits.popleft()
            return len(hits)

    def _record_failure(self, key: str) -> None:
        with self._lock:
            self._hits[key].append(time.monotonic())

    def _clear(self, key: str) -> None:
        """A success means this client is legitimate — give the budget back."""
        with self._lock:
            self._hits.pop(key, None)

    async def dispatch(self, request: Request, call_next):
        if not RATE_LIMIT_ENABLED or not any(
            request.url.path.endswith(suffix) for suffix in self.PROTECTED_SUFFIXES
        ):
            return await call_next(request)

        key = self._client_key(request)

        if self._recent_failures(key) >= self._max_requests:
            logger.warning(
                "Rate limit hit on %s from %s", request.url.path, key,
                extra={"extra_fields": {"path": request.url.path, "client": key}},
            )
            return JSONResponse(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                content={
                    "detail": "Too many failed attempts. "
                              "Please wait a minute and try again.",
                    "request_id": request_id_var.get(),
                },
                headers={"Retry-After": str(self._window_seconds)},
            )

        response = await call_next(request)

        if response.status_code in self.FAILURE_STATUSES:
            self._record_failure(key)
        elif response.status_code < 400:
            self._clear(key)

        return response
