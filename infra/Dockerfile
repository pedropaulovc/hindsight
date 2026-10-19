FROM ghcr.io/vectorize-io/hindsight-api:1.0.0-slim

LABEL org.opencontainers.image.source="https://github.com/pedropaulovc/hindsight"

# Temporary until upstream exposes native Jev long-context configuration.
# Remove when upstream ships native support: https://github.com/pedropaulovc/hindsight/issues/23
# The upstream image owns /app/api as hindsight; no root or new dependencies.
USER hindsight
COPY --chown=hindsight:hindsight infra/enable-jev-long-context.py /tmp/enable-jev-long-context.py
RUN /app/api/.venv/bin/python /tmp/enable-jev-long-context.py \
    && rm /tmp/enable-jev-long-context.py
