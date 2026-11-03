FROM oven/bun:1.4.4

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git ca-certificates gosu util-linux \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/gbrain

RUN git clone --depth 1 --branch v0.60.555.0 \
       https://github.com/garrytan/gbrain.git . \
    && bun install --frozen-lockfile \
    && cd admin \
    && bun install --frozen-lockfile \
    && cd .. \
    && bun run build:admin

COPY entrypoint.sh /usr/local/bin/gbrain-entrypoint

RUN chmod 755 /usr/local/bin/gbrain-entrypoint

ENV HOME=/home/bun
ENV GBRAIN_HOME=/home/bun/.gbrain

EXPOSE 3131

ENTRYPOINT ["/usr/local/bin/gbrain-entrypoint"]
