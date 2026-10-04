FROM elixir:1.19-otp-28-slim AS builder

RUN apt-get update -o Acquire::Retries=3 -y && apt-get install -y --no-install-recommends \
    gcc libc6-dev make git ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

RUN mix tailwind.install --if-missing && mix esbuild.install --if-missing

COPY priv priv
COPY lib lib
COPY assets assets

# esbuild resolves phoenix-colocated hooks from the compiled build, so compile comes first.
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
RUN mix release

FROM debian:trixie-slim

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

# Docker copies this ownership into an empty named volume on first mount, so SQLite can write.
RUN mkdir -p /data && chown nobody:nogroup /data

ENV MIX_ENV="prod"
ENV PHX_SERVER="true"

COPY --from=builder --chown=nobody:nogroup /app/_build/${MIX_ENV}/rel/three_sixes ./

USER nobody

EXPOSE 4000

CMD ["/app/bin/three_sixes", "start"]
