image_name := env("BUILD_IMAGE_NAME", "squisher")
image := env("IMAGE_FULL", "squisher:latest")
image_tag := env("BUILD_IMAGE_TAG", "latest")
base_dir := env("BUILD_BASE_DIR", ".")
filesystem := env("BUILD_FILESYSTEM", "btrfs")
just := just_executable()
profiles := env("BUILD_PROFILES", "")

[private]
default:
    @{{ just }} --list

_check-root:
    #!/usr/bin/env bash
    if [[ $EUID -ne 0 ]]; then
       echo "This script must be run as root" 
       exit 1
    fi

# Build OCI for bootc
[group('bootc')]
build-bootc *args:
    #!/usr/bin/env bash
    mkosi build -ff --profile bootc-ostree {{ args }}

[group('bootc')]
_bootc *ARGS:
    #!/usr/bin/env bash
    set -eoux pipefail

    BOOTC_INSTALL_OPTIONS=()
    BOOTC_INSTALL_OPTIONS+=("-v" "/var/lib/containers:/var/lib/containers" "-v" "/etc/containers:/etc/containers")

    if [[ -d /sys/fs/selinux ]]; then
      BOOTC_INSTALL_OPTIONS+=("-v" "/sys/fs/selinux:/sys/fs/selinux" "--security-opt" "label=type:unconfined_t")
    fi

    podman run \
        --rm --privileged --pid=host \
        -it \
        "${BOOTC_INSTALL_OPTIONS[@]}" \
        -v /dev:/dev \
        -v "${BUILD_BASE_DIR:-.}:/data" \
        {{image}} bootc {{ ARGS }}

# Load output into containers-storage
[group('bootc')]
load:
    #!/usr/bin/env bash
    set -x
    podman load -i "$(find mkosi.output -iname "{{ image_name }}*x86-64" -type d)" -q | cut -d: -f3 | xargs -I{} podman tag {} {{image}}

# Generate a bootable.img file
[group('bootc')]
generate-image-bootc $filesystem=filesystem:
    #!/usr/bin/env bash
    set -e
    {{ just }} _check-root
    if [ ! -e "{{ base_dir }}/bootable.img" ] ; then
        fallocate -l 20G "{{ base_dir }}/bootable.img"
    fi
    {{ just }} _bootc install to-disk --generic-image --bootloader grub --via-loopback /data/bootable.img --filesystem "${filesystem}" --wipe

# Lint the image
[group('bootc')]
lint:
    podman run --rm -it --entrypoint=bootc {{image}} container lint

# Rechunk the image
[group('bootc')]
rechunk: 
    #!/usr/bin/env bash
    IMG="{{image}}"
    export CHUNKAH_CONFIG_STR="$(podman inspect $IMG)"
    podman run --rm --mount=type=image,src=$IMG,dest=/chunkah \
        -e CHUNKAH_CONFIG_STR quay.io/coreos/chunkah build \
        --label containers.bootc=1 \
        --compressed --max-layers 30 \
        -t $IMG | podman load

# Build .raw files for systemd-sysupdate
[group('sysupdate')]
build-sysupdate *args:
    #!/usr/bin/env bash
    mkosi build -ff sysupdate --profile=sysupdate {{ args }}

[group('sysupdate')]
_find-raw-sysupdate:
    find "{{ base_dir }}/mkosi.output" -maxdepth 1 -iname "{{ image_name }}*x86-64.raw" | sort -nr | head -n1

# Open the generated .raw in a vm
[group('sysupdate')]
vm-sysupdate:
    dd if=/dev/zero of=$({{ just }} _find-raw-sysupdate) bs=1G count=0 seek=25
    # We use --no-tpm to ensure this will boot on older hardware (such as our VPS) 
    vmbuddy $({{ just }} _find-raw-sysupdate) --no-tpm

# Resize .raw file for writing to a live iso or system
[group('sysupdate')]
resize-raw-sysupdate:
    dd if=/dev/zero of=$({{ just }} _find-raw-sysupdate) bs=1G count=0 seek=12
