# Local-only extension of the verified development image. Do not redistribute
# the vendor archive or the resulting image. Build with the repo as the context
# and container/gowin.containerignore as --ignorefile.
ARG BASE_IMAGE=sha256:8ddc50649d4ae3fda9d5790f60ebeb7b8ee28a7dbd53f0547b4234945ffd6143
FROM ${BASE_IMAGE}

COPY logs/Gowin_V1.9.11.03_Education_Linux.tar.gz /tmp/gowin.tar.gz
RUN echo '6fd392f7473b24d847b6f8ebdc7a185c591826ba35d8d0e517961030d446f9f7  /tmp/gowin.tar.gz' | sha256sum -c - \
 && mkdir -p /opt/gowin \
 && tar -xzf /tmp/gowin.tar.gz -C /opt/gowin \
 && rm /tmp/gowin.tar.gz

COPY logs/gowin-runtime/*.deb /tmp/gowin-runtime/
COPY container/gowin-runtime.sha256 /tmp/gowin-runtime/SHA256SUMS
RUN cd /tmp/gowin-runtime \
 && sha256sum -c SHA256SUMS \
 && mkdir -p /opt/gowin-runtime \
 && while read -r checksum package; do \
      dpkg-deb --extract "$package" /opt/gowin-runtime; \
    done < SHA256SUMS

# Keep vendor shared libraries out of the environment used by Veryl, GCC and
# the kernel build. The calling script sets them only for gw_sh.
ENV GOWIN_HOME=/opt/gowin/IDE
WORKDIR /work
