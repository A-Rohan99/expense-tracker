"""
Application logging.

The app had no logging of any kind. For something that moves money that is a
problem in its own right: no audit trail of balance changes, and no way to
diagnose a 500 after the fact.

Two formats:
* development — one readable line per record
* production  — JSON, so the hosting platform's log search can filter on
  fields rather than regex the message

Every request gets a correlation id, echoed back in ``X-Request-ID``, so a user
reporting "it failed at 3pm" can be traced to exact log lines.
"""

from __future__ import annotations

import json
import logging
import sys
import uuid
from contextvars import ContextVar

from app.config import LOG_JSON, LOG_LEVEL

# Set per request by RequestContextMiddleware, read by the log formatter.
request_id_var: ContextVar[str] = ContextVar("request_id", default="-")
user_id_var: ContextVar[str] = ContextVar("user_id", default="-")


def new_request_id() -> str:
    return uuid.uuid4().hex[:12]


class _ContextFilter(logging.Filter):
    """Attach the current request/user ids to every record."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_var.get()
        record.user_id = user_id_var.get()
        return True


class _JsonFormatter(logging.Formatter):
    """One JSON object per line."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", "-"),
            "user_id": getattr(record, "user_id", "-"),
        }
        # Anything passed via logger.info("...", extra={...}).
        for key, value in getattr(record, "extra_fields", {}).items():
            payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


def configure_logging() -> None:
    """Install handlers. Safe to call more than once."""
    handler = logging.StreamHandler(sys.stdout)
    handler.addFilter(_ContextFilter())

    if LOG_JSON:
        handler.setFormatter(_JsonFormatter())
    else:
        handler.setFormatter(
            logging.Formatter(
                "%(asctime)s %(levelname)-8s [%(request_id)s] %(name)s: %(message)s",
                datefmt="%H:%M:%S",
            )
        )

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(LOG_LEVEL)

    # uvicorn installs its own handlers; route them through ours so the
    # formatting and correlation ids are consistent.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True


def audit(
    logger: logging.Logger,
    event: str,
    **fields,
) -> None:
    """
    Record a money-moving event.

    Kept separate from ordinary logging so these lines are easy to filter:
    every balance change should be reconstructable from them.
    """
    logger.info(event, extra={"extra_fields": {"audit": True, **fields}})
