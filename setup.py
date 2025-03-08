from setuptools import setup, find_packages

setup(
    name="gaia",
    version="0.1.0",
    packages=find_packages(),
    entry_points={
        "console_scripts": [
            "gaia=gaia.cli:app",
            "atmos-cli=gaia.cli:app_with_deprecation_warning",  # For backwards compatibility
        ],
    },
    install_requires=[
        "typer>=0.9.0",
        "pyyaml>=6.0",
        "boto3>=1.26.0",
        "python-terraform>=0.10.1",
        "copier>=8.1.0",
        "networkx>=3.1",
        "celery>=5.3.1",
        "redis>=4.6.0",
        "flower>=2.0.1",
    ],
    python_requires=">=3.8",
    author="TF-Atmos Team",
    author_email="tf-atmos@example.com",
    description="Python CLI for Terraform Atmos with Celery support",
    keywords="terraform, atmos, infrastructure, aws, celery",
    url="https://github.com/example/tf-atmos",
    classifiers=[
        "Development Status :: 3 - Alpha",
        "Intended Audience :: Developers",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
    ],
)