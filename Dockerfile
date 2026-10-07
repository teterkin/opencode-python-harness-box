# opencode с харнессом TDD/PRD внутри python-dev контейнера.
FROM ubuntu:24.04

ARG OPENCODE_VERSION=1.18.34
ARG HARNESS_REF=78452bf1
ARG DEBIAN_FRONTEND=noninteractive

ENV LANG=C.UTF-8 \
    PATH=/home/box/.opencode/bin:$PATH

RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-pip \
        python3-dev \
        build-essential \
        git \
        make \
        curl \
        ca-certificates \
        ripgrep \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN usermod -l box ubuntu \
    && groupmod -n box ubuntu \
    && usermod -d /home/box -m box \
    && mkdir -p /home/box/.local/share/opencode /home/box/.cache \
    && chown -R box:box /home/box/.local /home/box/.cache \
    && mkdir -p /workspace \
    && chown box:box /workspace

RUN HOME=/home/box sh -c \
        'curl -fsSL https://opencode.ai/install | bash -s -- --version "$OPENCODE_VERSION" --no-modify-path' \
    && test "$(opencode --version)" = "$OPENCODE_VERSION"

RUN git clone --quiet https://github.com/teterkin/opencode-harness /opt/opencode-harness \
    && git -C /opt/opencode-harness checkout --quiet --detach "$HARNESS_REF" \
    && HOME=/home/box /opt/opencode-harness/install.sh \
    && chmod -R a+rX /opt/opencode-harness

RUN chmod 755 /home/box

USER box
WORKDIR /workspace

CMD ["opencode"]
