FROM debian:wheezy-slim AS tools

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    jq \
    libssl3 \
    tzdata \
    openssl && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

FROM mcr.microsoft.com/azure-cli:2.65.0

COPY --from=tools /usr/bin/jq /usr/bin/jq
COPY --from=tools /usr/bin/openssl /usr/bin/openssl

COPY --from=tools /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/lib/x86_64-linux-gnu/libssl.so.3
COPY --from=tools /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/lib/x86_64-linux-gnu/libcrypto.so.3

RUN ln -sf /usr/lib/x86_64-linux-gnu/libssl.so.3 /usr/lib/libssl.so.3 && \
    ln -sf /usr/lib/x86_64-linux-gnu/libcrypto.so.3 /usr/lib/libcrypto.so.3 && \
    ldconfig

CMD ["tail", "-f", "/dev/null"]
