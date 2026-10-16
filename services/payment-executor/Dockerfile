FROM golang:1.25-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY gen ./gen
COPY main.go ./
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/executor .

FROM alpine:3.22
WORKDIR /app
COPY --from=build /out/executor /usr/local/bin/executor
COPY data ./data
ENV PORT=8083
ENV HEALTH_PORT=8093
EXPOSE 8083 8093
CMD ["executor"]
