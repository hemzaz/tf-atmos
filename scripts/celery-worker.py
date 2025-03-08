#!/usr/bin/env python3
"""
Celery worker script for Gaia
"""

import os
import sys
import logging
from gaia.cli import celery_app
from gaia.logger import setup_logger

# Ensure all tasks are imported
import gaia.tasks

if __name__ == "__main__":
    logger = setup_logger()
    logger.info("Starting Gaia Celery worker...")
    
    # Add Gaia to python path
    sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
    
    argv = [
        "worker",
        "--loglevel=INFO",
        "--concurrency=4",
        "-n", "gaia-worker@%h",
    ]
    
    celery_app.worker_main(argv)