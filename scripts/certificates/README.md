# Certificate Management

## Migration Status

The certificate management scripts in this directory are being migrated to Python-based implementations in the Gaia CLI. The current status is:

| Script | Status | Replacement Command |
|--------|--------|---------------------|
| `rotate-cert.sh` | ✅ Migrated | `gaia certificate rotate` |
| `rotate-ssh-key.sh` | ⚠️ Pending | Will be replaced by `gaia certificate rotate-ssh-key` |
| `generate-ssh-key.sh` | ⚠️ Pending | Will be replaced by `gaia certificate generate-ssh-key` |
| `export-cert.sh` | ⚠️ Pending | Will be replaced by `gaia certificate export` |
| `export-ssh-key.sh` | ⚠️ Pending | Will be replaced by `gaia certificate export-ssh-key` |
| `monitor-certificates.sh` | ⚠️ Pending | Will be replaced by `gaia certificate monitor` |

## Usage

For scripts that have been migrated, please use the corresponding Gaia command. For those still pending migration, continue using the bash scripts for now but be aware they will be deprecated once the Python implementations are complete.

## Future Plans

All of these scripts will eventually be replaced by a more robust Python-based implementation with better error handling, security, and integration with the rest of the Gaia system.
