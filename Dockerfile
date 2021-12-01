FROM nimlang/nim AS builder

COPY . /code
WORKDIR /code

# Removes any already existing binary so that when compilation fails the container stops
RUN rm -f /code/nimd
RUN nim -d:release --opt:size --passL:"-static" c -o:nimd src/main
RUN cp /code/nimd /sbin/nimd

FROM alpine:latest

COPY --from=builder /code/nimd /sbin/nimd
# ENTRYPOINT ["/bin/sh", "-l"]
ENTRYPOINT [ "/sbin/nimd", "--extra"]
