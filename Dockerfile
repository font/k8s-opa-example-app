# Build the app binary
FROM golang:alpine as builder

WORKDIR /workspace

# Copy the Go Modules manifests
COPY go.mod go.mod
# Copy the go source
COPY main.go main.go

# Build
RUN go build -o app main.go

FROM alpine:latest
WORKDIR /
COPY --from=builder /workspace/app .

CMD ["/app"]
