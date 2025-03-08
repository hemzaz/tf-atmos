"""
Logging utilities for Atmos CLI.
Provides consistent logging throughout the application.
"""

import os
import sys
import logging
from typing import Optional
from pathlib import Path
import datetime
from rich.console import Console
from rich.logging import RichHandler
from rich.theme import Theme

# Custom theme for rich
RICH_THEME = Theme({
    "info": "cyan",
    "warning": "yellow",
    "error": "bold red",
    "critical": "bold white on red",
    "success": "green",
    "debug": "dim blue",
    "section": "bold cyan",
})

# Console for pretty printing
console = Console(theme=RICH_THEME)

# Configure log levels
VERBOSE = 15
SUCCESS = 25
SECTION = 30

# Add custom log levels
logging.addLevelName(VERBOSE, "VERBOSE")
logging.addLevelName(SUCCESS, "SUCCESS")
logging.addLevelName(SECTION, "SECTION")


class AtmosLogger(logging.Logger):
    """Extended logger with custom log levels."""
    
    def verbose(self, msg, *args, **kwargs):
        """Log a verbose message (more detailed than info, less than debug)."""
        if self.isEnabledFor(VERBOSE):
            self._log(VERBOSE, msg, args, **kwargs)
    
    def success(self, msg, *args, **kwargs):
        """Log a success message."""
        if self.isEnabledFor(SUCCESS):
            self._log(SUCCESS, msg, args, **kwargs)
    
    def section(self, msg=None, *args, **kwargs):
        """Log a section header."""
        if self.isEnabledFor(SECTION):
            if msg:
                self._log(SECTION, f"\n=== {msg} ===", args, **kwargs)
            else:
                self._log(SECTION, "\n" + "=" * 50, args, **kwargs)


# Register custom logger class
logging.setLoggerClass(AtmosLogger)


def setup_logging(log_level: str = "INFO", log_file: Optional[str] = None) -> None:
    """Configure logging for the application."""
    # Convert string log level to numeric value
    numeric_level = getattr(logging, log_level.upper(), logging.INFO)
    
    # Create log directory if necessary
    if log_file:
        log_dir = os.path.dirname(log_file)
        if log_dir and not os.path.exists(log_dir):
            os.makedirs(log_dir)
    
    # Configure rich handler for console output
    rich_handler = RichHandler(
        rich_tracebacks=True,
        console=console,
        show_time=False,
        show_path=False,
    )
    
    # Basic config for console logging
    handlers = [rich_handler]
    
    # Add file handler if log file specified
    if log_file:
        file_handler = logging.FileHandler(log_file)
        file_formatter = logging.Formatter(
            '%(asctime)s [%(levelname)s] %(name)s: %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler.setFormatter(file_formatter)
        handlers.append(file_handler)
    
    # Configure the root logger
    logging.basicConfig(
        level=numeric_level,
        format="%(message)s",
        datefmt="[%X]",
        handlers=handlers
    )


def get_logger(name: str) -> AtmosLogger:
    """Get a logger instance with the specified name."""
    return logging.getLogger(name)


def get_log_file(log_dir: str = "logs") -> str:
    """Generate a timestamped log file path."""
    # Ensure log directory exists
    Path(log_dir).mkdir(parents=True, exist_ok=True)
    
    # Generate timestamped filename
    timestamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    return os.path.join(log_dir, f"atmos-{timestamp}.log")


# Initialize logging with default settings
# This can be reconfigured later with setup_logging()
log_file = get_log_file()
setup_logging(log_level=os.environ.get("ATMOS_LOG_LEVEL", "INFO"), log_file=log_file)