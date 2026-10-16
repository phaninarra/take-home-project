FROM alpine:3.22 AS build
RUN apk add --no-cache gcc musl-dev libmicrohttpd-dev libxml2-dev openssl-dev
WORKDIR /src
COPY server.c ./
RUN gcc -O2 -Wall -Wextra -o /out-registry server.c \
    $(pkg-config --cflags --libs libxml-2.0) \
    -lmicrohttpd -lcrypto

FROM alpine:3.22
RUN apk add --no-cache libmicrohttpd libxml2 openssl
WORKDIR /app
COPY --from=build /out-registry /usr/local/bin/registry
COPY data ./data
ENV PORT=8082
EXPOSE 8082
CMD ["registry"]
