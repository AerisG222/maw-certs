FROM alpine

RUN apk --no-cache add \
    bash \
    openssl

WORKDIR /src
COPY gen_certs.sh .
COPY dev ./dev/
COPY prod ./prod/
COPY stage ./stage/
COPY test ./test/

ENTRYPOINT [ "/src/gen_certs.sh" ]
