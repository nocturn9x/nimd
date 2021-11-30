FROM nimlang/nim AS builder

COPY . /code
WORKDIR /code

RUN nim c -o:nimd --passL:"-static" src/main.nim
RUN cp /code/nimd /sbin/nimd

FROM alpine:latest

COPY --from=builder /code/nimd /sbin/nimd
# ENTRYPOINT ["/bin/sh", "-l"]
ENTRYPOINT [ "/sbin/nimd", "--extra"]
