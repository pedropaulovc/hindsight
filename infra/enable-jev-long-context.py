"""Apply the deployment-only Jev header patch to the pinned upstream image."""

import ast
from pathlib import Path


SOURCE = Path("/app/api/hindsight_api/engine/cross_encoder.py")
EXPECTED = b"headers=reranker_bank_attribution_headers()"
REPLACEMENT = (
    b'headers={**reranker_bank_attribution_headers(), '
    b'"TypeSafe-Danger-Zone-Long-Context": "true"}'
)


def fail(message: str) -> None:
    raise SystemExit(f"Jev long-context patch refused: {message}")


def main() -> None:
    # This source path and its hindsight ownership come from the pinned upstream
    # docker/standalone/Dockerfile. Do not import the configuration-heavy API.
    try:
        source = SOURCE.read_bytes()
        module = ast.parse(source, filename=str(SOURCE))
    except (OSError, SyntaxError) as error:
        fail(f"cannot read/parse {SOURCE}: {error}")

    classes = [
        node for node in module.body
        if isinstance(node, ast.ClassDef) and node.name == "TypeSafeCrossEncoder"
    ]
    if len(classes) != 1:
        fail("expected exactly one TypeSafeCrossEncoder class")
    methods = [
        node for node in classes[0].body
        if isinstance(node, ast.AsyncFunctionDef) and node.name == "_ask"
    ]
    if len(methods) != 1:
        fail("expected exactly one async TypeSafeCrossEncoder._ask method")

    method = methods[0]
    lines = source.splitlines(keepends=True)
    start = sum(map(len, lines[:method.lineno - 1]))
    end = sum(map(len, lines[:method.end_lineno]))
    original = source[start:end]
    if original.count(EXPECTED) != 1:
        fail("expected exactly one headers=reranker_bank_attribution_headers() in TypeSafeCrossEncoder._ask")
    patched = original.replace(EXPECTED, REPLACEMENT, 1)
    # Preserve every byte outside the single headers expression, including the
    # session authentication, bank attribution, and other providers' requests.
    try:
        SOURCE.write_bytes(source[:start] + patched + source[end:])
    except OSError as error:
        fail(f"cannot write {SOURCE}: {error}")
    print(f"Enabled TypeSafe-Danger-Zone-Long-Context in {SOURCE}")


if __name__ == "__main__":
    main()
