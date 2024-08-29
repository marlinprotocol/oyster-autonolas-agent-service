# Autonolas Agent Service on Oyster

This repository packages [autonolas agent service](https://docs.autonolas.network/open-autonomy/) in an enclave image.

The agent service used here is a simple hello world demo - https://docs.autonolas.network/demos/hello-world/

## Prerequisites

- Nix

The enclave is built using nix for reproducibility. It does NOT use the standard `nitro-cli` based pipeline, and instead uses [monzo/aws-nitro-util](https://github.com/monzo/aws-nitro-util) in order to produce bit-for-bit reproducible enclaves.

The following nix `experimental-features` must be enabled:
- nix-command
- flakes

## Build

TODO: arm64 support, cross-platform build support

```bash
# On amd64, For amd64
# The request folder will contain the enclave image and pcrs
nix build -vL
```
