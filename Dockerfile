ARG JELLYFIN_TAG=12.4

FROM jellyfin/jellyfin:${JELLYFIN_TAG}@sha256:fea863d0cd9ec445985d9c75fc6ed64e38a1d2766cf0c250a33d553f4fc1b771 AS base

# Built on the Jellyfin image itself: same glibc and libstdc++ as the runtime,
# and its dpkg database tells which runtime libraries Mesa needs on top.
FROM base AS mesa
ARG MESA_COMMIT=ef594386e28b9a01ab00d2190d5960d3eee8fe04
ENV P=/opt/mesa

RUN dpkg-query -W -f='${Package}\n' | sort -u > /tmp/base-packages.txt \
 && echo "deb-src http://deb.debian.org/debian trixie main" > /etc/apt/sources.list.d/src.list \
 && apt-get update \
 && apt-get build-dep -y mesa \
 && apt-get install -y git rustc bindgen cbindgen glslang-tools libclc-19-dev libllvmspirvlib-19-dev spirv-tools \
      python3-mako python3-yaml python3-ply python3-pycparser

WORKDIR /build/mesa
COPY fixes.patch /tmp/fixes.patch
RUN git init -q \
 && git remote add origin https://gitlab.freedesktop.org/mesa/mesa.git \
 && git fetch -q --depth 1 origin ${MESA_COMMIT} \
 && git checkout -q FETCH_HEAD \
 && git apply /tmp/fixes.patch

RUN meson setup build -Dprefix=$P -Dbuildtype=release \
      -Dgallium-drivers=zink -Dvulkan-drivers=panfrost -Dgallium-rusticl=true -Dstatic-libclc=all \
      -Dplatforms= -Dglx=disabled -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
      -Dgbm=disabled -Dllvm=enabled -Dvideo-codecs= \
 && ninja -C build install \
 && rm -rf $P/lib/aarch64-linux-gnu/dri

# Runtime libraries the Jellyfin image lacks, taken from the Debian packages that provide them.
RUN LIB=$P/lib/aarch64-linux-gnu \
 && ldd $LIB/libRusticlOpenCL.so.1 $LIB/libvulkan_panfrost.so \
    | awk '/=>/ {print $3}' | grep -v "^$P" | xargs realpath | sort -u > /tmp/needed-libs.txt \
 && for l in $(cat /tmp/needed-libs.txt); do dpkg -S "$l" 2>/dev/null | head -1 | cut -d: -f1; done | sort -u > /tmp/needed-pkgs.txt \
 && (grep -v -x -F -f /tmp/base-packages.txt /tmp/needed-pkgs.txt > /tmp/extra-pkgs.txt || true) \
 && cat /tmp/extra-pkgs.txt \
 && mkdir -p /layer/opt /layer/etc/OpenCL/rusticl /tmp/debs \
 && cp -a $P /layer/opt/ \
 && cd /tmp/debs \
 && apt-get download $(cat /tmp/extra-pkgs.txt) \
 && for d in /tmp/debs/*.deb; do dpkg-deb -x "$d" /layer; done \
 && rm -rf /layer/usr/share/doc /layer/usr/share/man /layer/usr/share/lintian \
 && echo "$LIB/libRusticlOpenCL.so.1" > /layer/etc/OpenCL/rusticl/rusticl.icd

FROM base
COPY --from=mesa /layer/ /
# opencl-c-base.h, needed when rusticl compiles OpenCL kernels
COPY --from=mesa /usr/lib/llvm-19/lib/clang/19/include/ /usr/lib/llvm-19/lib/clang/19/include/
ENV OCL_ICD_VENDORS=/etc/OpenCL/rusticl \
    RUSTICL_ENABLE=zink \
    VK_DRIVER_FILES=/opt/mesa/share/vulkan/icd.d/panfrost_icd.aarch64.json
