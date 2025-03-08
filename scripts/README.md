# Atmos CLI Scripts

This directory contains scripts that supplement the Python-based Atmos CLI implementation.

## Directory Structure

- **certificates/**: Certificate and SSH key management scripts (not yet implemented in Python)
- **compatibility/**: Legacy bash scripts maintained for backward compatibility
- **templates/**: Template files used by both bash and Python implementations

## Migration Status

Most functionality has been migrated to the Python-based implementation in the `gaia/` directory:

| Category | Status | Python Implementation |
|----------|--------|----------------------|
| Core Utilities | ✅ Migrated | `logger.py`, `utils.py`, `config.py` |
| Component Operations | ✅ Migrated | `operations.py`, `discovery.py` |
| State Management | ✅ Migrated | `state.py` |
| Environment Management | ⚠️ Partial | Missing some functionality |
| Certificate Management | ❌ Not Migrated | Still using bash scripts |
| Installation | ⚠️ Partial | Missing tool installation |

## Usage

The bash scripts in this directory are maintained for backward compatibility and to provide functionality not yet available in the Python implementation. New development should use the Python-based CLI where possible.

```bash
# Preferred approach (Python)
gaia workflow apply-environment --tenant acme --account prod --environment use1

# Backward compatible approach (Bash)
./scripts/compatibility/component-operations.sh apply
```

## Maintenance

When adding functionality to the Python implementation, please deprecate the corresponding bash script by moving it to the `compatibility/` directory rather than deleting it immediately.