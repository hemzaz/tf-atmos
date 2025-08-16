#!/usr/bin/env python3
"""
Setup script for Gaia CLI
"""

from setuptools import setup, find_packages
import os

# Read version from __init__.py
version = {}
with open("__init__.py") as f:
    exec(f.read(), version)

# Read requirements
with open("requirements.txt") as f:
    requirements = f.read().splitlines()

# Read README if it exists
readme_path = "README.md"
long_description = ""
if os.path.exists(readme_path):
    with open(readme_path) as f:
        long_description = f.read()

setup(
    name="gaia-cli",
    version=version.get("__version__", "2.0.0"),
    author=version.get("__author__", "Infrastructure Team"),
    description=version.get("__description__", "Simplified Python CLI wrapper for Atmos operations"),
    long_description=long_description,
    long_description_content_type="text/markdown",
    py_modules=["cli"],
    install_requires=requirements,
    entry_points={
        "console_scripts": [
            "gaia=cli:app",
        ],
    },
    python_requires=">=3.8",
    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Tools",
        "Topic :: System :: Systems Administration",
    ],
)