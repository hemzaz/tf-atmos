# Deprecated Scripts

This directory contains deprecated scripts that are maintained for backward compatibility only.

## Usage Warning

⚠️ **WARNING**: These scripts are deprecated and will be removed in a future release.

## Migration Guide

Please use the equivalent Python-based commands in the Gaia CLI:

| Deprecated Script | Replacement Command |
|-------------------|---------------------|
| `atmos-ops` | `gaia-ops` or directly use `gaia workflow` commands |
| `scripts/certificates/rotate-cert.sh` | `gaia certificate rotate` |
| `scripts/certificates/rotate-ssh-key.sh` | `gaia certificate rotate-ssh-key` |

## Compatibility Period

These compatibility scripts will be maintained through one major release cycle to allow for proper migration, but may be removed at any time thereafter.

Please update your scripts and documentation to use the new commands as soon as possible.
