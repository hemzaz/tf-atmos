# Gaia Python CLI Commands

Commands for the Gaia Python CLI tool (this project's custom tooling).

## Workflow Commands
```bash
gaia workflow lint --fix false        # Lint with optional auto-fix
gaia workflow validate --tenant <tenant> --account <account> --environment <environment>
```

## Available via Setup.py
```bash
gaia                                  # Main CLI entry point
atmos-cli                            # Backwards compatibility alias
```

## Installation
```bash
pip install -e .                     # Install in development mode
```

## Dependencies
- Python 3.8+
- Typer, PyYAML, Boto3
- Celery, Redis for task processing
- Copier for templating