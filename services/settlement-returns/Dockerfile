FROM debian:trixie-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends fp-compiler fp-units-fcl libc6-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY server.pas ./
RUN fpc -O2 -oreturnsservice server.pas

FROM debian:trixie-slim
WORKDIR /app
COPY --from=build /src/returnsservice /usr/local/bin/returnsservice
COPY data ./data
ENV PORT=8084
EXPOSE 8084
CMD ["returnsservice"]
