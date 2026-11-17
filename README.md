# Squisher - a tiny Fedora server

The goal of this system is to provide an image on which containers are run, similar to [flatcar](https://www.flatcar.org/). The base should be minimal with very few packages and simply offer the necessary runtime environment for podman quadlets. Updates are provided via systemd-sysupdate using raw disk images of /usr and UKI .efi files.

# CI

Builds are run weekly, on update to the repository, or manually. A new release is created and to install this release you must only run `updatectl update`.
