# bsoe-build: the BrightSign OpenEmbedded build environment used to compile the
# custom cross-compile SDK from BrightSign OS source. The OS source + build tree
# are mounted in from the shared cache at run time (scripts/build-sdk.sh), not
# baked into the image, so the image stays small and the ~20GB download happens
# once per build box into the cache.
#
# Built by `make build` (scripts/build-sdk.sh) as the `bsoe-build` image.

FROM debian:bullseye

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=builder

# Enable i386 multiarch (the OE toolchain pulls some 32-bit host libs) and
# install the OpenEmbedded host build dependencies in one layer.
RUN dpkg --add-architecture i386 && \
    apt-get update && \
    apt-get install -y \
        locales \
        avahi-daemon \
        build-essential \
        diffstat \
        texi2html \
        cvs \
        subversion \
        gawk \
        chrpath \
        screen \
        patchutils \
        ruby \
        libgl1-mesa-dev \
        libglu1-mesa-dev \
        uuid-dev \
        libsdl1.2-dev \
        lzop \
        autofs \
        zip \
        curl \
        tftpd-hpa \
        nfs-server \
        ed \
        dbus-x11 \
        time \
        texinfo \
        bc \
        libpcre16-3 \
        rsync \
        wget \
        pigz \
        moreutils \
        libc6:i386 \
        libstdc++6:i386 \
        libglib2.0-0:i386 \
        g++-multilib \
        libxcb-icccm4 \
        libxcb-image0 \
        libxcb-shape0 \
        libxcb-keysyms1 \
        libxcb-render-util0 \
        libxcb-xinerama0 \
        libxcb-xkb1 \
        libxkbcommon-x11-0 \
        libxkbcommon0 \
        python3-requests \
        git \
        apticron \
        etckeeper \
        lsb-release \
        cpio \
        sudo \
        file && \
    sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    echo 'LANG="en_US.UTF-8"' > /etc/default/locale && \
    dpkg-reconfigure --frontend=noninteractive locales && \
    echo "dash dash/sh boolean false" | debconf-set-selections && \
    dpkg-reconfigure --frontend=noninteractive dash && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Build as a user matching the host UID/GID so files written to the mounted
# source tree are owned by the invoking user, not root.
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -u ${USER_ID} -g ${USERNAME} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

RUN mkdir -p /home/${USERNAME}/bsoe && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}
WORKDIR /home/${USERNAME}/bsoe
USER ${USERNAME}

# Available for manual/in-container patch application; the normal flow applies
# the recipe layer host-side (scripts/build-sdk.sh) before the build runs.
COPY scripts/setup-patches.sh /usr/local/bin/setup-patches.sh
RUN sudo chmod +x /usr/local/bin/setup-patches.sh

CMD ["/bin/bash"]
