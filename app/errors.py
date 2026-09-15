"""
Global exception handling.

Without these, an unhandled exception returned Starlette's plain-text
``Internal Server Error`` — a different shape from the ``{"detail": ...}`` body
every HTTPException produces, and nothing was recorded anywhere durable.

The contract here: clients always get ``{"detail": str, "request_id": str}``.
The request id is the thread back to the server-side log line, so a user can
report a failure without us needing to reproduce it.
"""

from __future__ import annotations

import logging

from fastapi import FastAPI, Request, status
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.logging_config import request_id_var

logger = logging.getLogger("app.errors")


def _body(detail: str) -> dict:
    return {"detail": detail, "request_id": request_id_var.get()}


def register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(StarletteHTTPException)
    async def http_exception_handler(request: Request, exc: StarletteHTTPException):
        # Deliberate, already-shaped errors. Log 5xx only; a 404 or a 401 is
        # routine and would drown the signal.
        if exc.status_code >= 500:
            logger.error("HTTP %s on %s: %s", exc.status_code, request.url.path, exc.detail)
        return JSONResponse(
            status_code=exc.status_code,
            content=_body(str(exc.detail)),
            headers=getattr(exc, "headers", None),
        )

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ):
        # Keep FastAPI's per-field list — the client unwraps it to show which
        # field was wrong — but add the request id for consistency.
        #
        # exc.errors() embeds live Python objects in `ctx` (the original
        # ValueError, a Decimal bound for a gt/lt constraint), which plain
        # json.dumps cannot serialise. Without jsonable_encoder every
        # validation error turns into a 500.
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content=jsonable_encoder(
                {
                    "detail": exc.errors(),
                    "request_id": request_id_var.get(),
                }
            ),
        )

    @app.exception_handler(IntegrityError)
    async def integrity_error_handler(request: Request, exc: IntegrityError):
        # A violated unique or check constraint is the caller's problem, not a
        # server fault — 409, not the 500 this used to produce.
        logger.warning(
            "Integrity error on %s: %s", request.url.path, exc.orig, exc_info=False
        )
        return JSONResponse(
            status_code=status.HTTP_409_CONFLICT,
            content=_body("That change conflicts with existing data."),
        )

    @app.exception_handler(SQLAlchemyError)
    async def database_error_handler(request: Request, exc: SQLAlchemyError):
        logger.exception("Database error on %s", request.url.path)
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content=_body("The database is unavailable. Please try again."),
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception):
        # Full detail to the log, nothing internal to the caller.
        logger.exception("Unhandled error on %s", request.url.path)
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content=_body("Something went wrong. Please try again."),
        )
