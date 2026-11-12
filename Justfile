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

# Build .raw files for systemd-sysupdate
[group('sysupdate')]
build-sysupdate *args:
    #!/usr/bin/env bash
    mkosi build -ff sysupdate --profile=sysupdate {{ args }}

# Checksum and sign the build artifacts for systemd-sysupdate
sign-build-sysupdate:
    #!/usr/bin/env bash
    pushd "{{ base_dir }}/mkosi.output"
    # Generate sha sums for each file (uki, usr, usr verity, usr verity sig) in SHA256SUMS
    sha256sum --binary $(basename -a $(find "." -iname "{{ image_name }}*usr*.raw*" -o -iname "{{ image_name }}*.efi")) > "./SHA256SUMS"

    # Sign the SHA256SUMS file
    gpg --output "./SHA256SUMS.gpg" --detach-sign "./SHA256SUMS"
    popd


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
