# maw-certs

![CI](https://github.com/AerisG222/maw-certs/workflows/CI/badge.svg?branch=master)

Container for creating backend self signed certs

# Usage

There are 2 primary ways to use this image.  The first is to generate certificates for local development
where the certs should be stored on the user's filesystem.  The second is to generate certificates when
running the site entierly in containers using managed volumes.

## local filesystem

This will store the generated certificates on the local filesystem - `/home/mmorano/_maw/xxx` in this example.

`podman run -it --rm --volume /home/mmorano/_maw/xxx:/maw-certs:rw,z maw-certs-dev local local`

Note: once this completes, you will need to manually fix/replace the symlinks for the active certs!

## managed volume

This will store the certificates in a managed volume named `volname`.

`podman run -it --rm --volume volname:/maw-certs:rw,z maw-certs-dev dev dev`

Note: for the symlinks to work as expected, make sure consuming volumes mount this in the `/maw-certs`
directory in the container.

## trust

In order to trust these certificates on a local machine, you will additionally need to run the following:

```
cp /path/to/certs/ca_*.crt /usr/share/pki/ca-trust-source/anchors
sudo update-ca-trust
```
