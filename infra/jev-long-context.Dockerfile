ARG BASE_IMAGE
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.source="https://github.com/pedropaulovc/hindsight"

# The upstream image owns /app/api as hindsight; no root or new dependencies.
USER hindsight
COPY --chown=hindsight:hindsight infra/enable-jev-long-context.py /tmp/enable-jev-long-context.py
RUN /app/api/.venv/bin/python /tmp/enable-jev-long-context.py \
    && rm /tmp/enable-jev-long-context.py
