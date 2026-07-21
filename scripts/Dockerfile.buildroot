# syntax=docker/dockerfile:1.7

FROM registry.gitlab.com/buildroot.org/buildroot/base:20250218.2110 AS builder

ARG BUILDROOT_URL=https://gitlab.com/buildroot.org/buildroot.git
ARG BUILDROOT_REF=2026.05
ARG BUILDROOT_DEFCONFIG

USER root
RUN install -d -o br-user -g br-user \
        /workspace \
        /home/br-user/.buildroot-dl

USER br-user
WORKDIR /workspace

RUN test -n "${BUILDROOT_DEFCONFIG}" || \
        { echo 'BUILDROOT_DEFCONFIG build argument is required' >&2; exit 1; }

RUN git init buildroot && \
    git -C buildroot remote add origin "${BUILDROOT_URL}" && \
    git -C buildroot fetch --depth 1 origin "${BUILDROOT_REF}" && \
    git -C buildroot checkout --detach FETCH_HEAD

RUN make -C buildroot O=/workspace/output "${BUILDROOT_DEFCONFIG}"

RUN --mount=type=cache,target=/home/br-user/.buildroot-dl,uid=1000,gid=1000,sharing=locked \
    make -C buildroot \
        O=/workspace/output \
        BR2_DL_DIR=/home/br-user/.buildroot-dl && \
    rm -rf \
        /workspace/output/build \
        /workspace/output/host \
        /workspace/output/staging \
        /workspace/output/target

FROM scratch AS export
COPY --from=builder /workspace/output/images /images
