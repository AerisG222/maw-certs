FROM alpine

RUN apk --no-cache add \
    bash \
    openssl

WORKDIR /src
COPY gen_certs.sh .
COPY dev ./dev/
COPY local ./local/
COPY prod ./prod/

ENTRYPOINT [ "/src/gen_certs.sh" ]
