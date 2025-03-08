"""
Utility functions for Atmos CLI.
Contains common utilities used across multiple modules.
"""

import os
import re
import subprocess
import tempfile
import shutil
from pathlib import Path
from typing import List, Dict, Any, Optional, Union, Tuple
import ipaddress
from dataclasses import dataclass

from gaia.logger import get_logger

logger = get_logger(__name__)


@dataclass
class CommandResult:
    """Result of running a command."""
    returncode: int
    stdout: str
    stderr: str
    
    @property
    def success(self) -> bool:
        """Check if command completed successfully."""
        return self.returncode == 0


def run_command(
    cmd: List[str],
    timeout: Optional[int] = None,
    env: Optional[Dict[str, str]] = None,
    cwd: Optional[str] = None,
    check: bool = True,
    memory_limit: Optional[int] = None,
    output_limit: int = 30000,
) -> CommandResult:
    """
    Run a command and return its output.
    
    Args:
        cmd: Command to run as a list of strings
        timeout: Command timeout in seconds
        env: Environment variables
        cwd: Working directory
        check: Whether to raise an exception if command fails
        memory_limit: Memory limit in MB (default None = no limit)
        output_limit: Maximum number of output characters to capture (default 30000)
        
    Returns:
        CommandResult object with returncode, stdout, and stderr
        
    Raises:
        subprocess.CalledProcessError: If command fails and check is True
    """
    # Merge environment variables
    merged_env = os.environ.copy()
    if env:
        merged_env.update(env)
    
    # Add memory limit if specified (linux only)
    if memory_limit and os.name == 'posix':
        # Prepend ulimit command to limit virtual memory
        # 1024 KB = 1 MB, so multiply memory_limit by 1024
        # limit_cmd = f"ulimit -v {memory_limit * 1024} && "
        # Instead of prepending a shell command, use resource module in Python 3
        import resource
        
        # Convert MB to bytes (memory_limit * 1024 * 1024)
        soft, hard = resource.getrlimit(resource.RLIMIT_AS)
        new_limit = memory_limit * 1024 * 1024
        
        try:
            resource.setrlimit(resource.RLIMIT_AS, (new_limit, hard))
            logger.debug(f"Set memory limit to {memory_limit} MB")
        except Exception as e:
            logger.warning(f"Could not set memory limit to {memory_limit} MB: {e}")
    
    logger.debug(f"Running command: {' '.join(cmd)}")
    
    try:
        process = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            env=merged_env,
            cwd=cwd,
            check=check,
        )
        
        # Trim output if it exceeds the limit
        stdout = process.stdout[:output_limit]
        stderr = process.stderr[:output_limit]
        
        # Add a note if output was truncated
        if len(process.stdout) > output_limit:
            stdout += f"\n... (output truncated, {len(process.stdout) - output_limit} characters omitted)"
        if len(process.stderr) > output_limit:
            stderr += f"\n... (error output truncated, {len(process.stderr) - output_limit} characters omitted)"
        
        result = CommandResult(
            returncode=process.returncode,
            stdout=stdout,
            stderr=stderr,
        )
        
        if result.success:
            logger.debug(f"Command succeeded with exit code {result.returncode}")
        else:
            logger.debug(f"Command failed with exit code {result.returncode}")
            logger.debug(f"Stderr: {result.stderr[:1000]}")  # Only log the first 1000 chars of stderr
        
        return result
        
    except subprocess.TimeoutExpired as e:
        logger.error(f"Command timed out after {timeout} seconds: {' '.join(cmd)}")
        return CommandResult(
            returncode=124,  # Standard timeout exit code
            stdout="",
            stderr=f"Timeout expired after {timeout} seconds",
        )
    except subprocess.CalledProcessError as e:
        logger.error(f"Command failed with exit code {e.returncode}: {' '.join(cmd)}")
        # Limit error output logging
        logger.debug(f"Stderr: {e.stderr[:1000] if e.stderr else ''}")
        raise


def validate_path(
    path: Union[str, Path],
    base_dir: Optional[Union[str, Path]] = None,
    must_exist: bool = False,
    allow_symlinks: bool = False,
) -> bool:
    """
    Validate if a path is safe to use.
    
    Args:
        path: Path to validate
        base_dir: Base directory that the path must be within
        must_exist: Whether the path must exist
        allow_symlinks: Whether to allow symlinks
        
    Returns:
        True if path is valid, False otherwise
    """
    try:
        path = Path(path).resolve()
        
        # Check if path exists if required
        if must_exist and not path.exists():
            logger.error(f"Path does not exist: {path}")
            return False
        
        # Check for symlinks if not allowed
        if not allow_symlinks and path.is_symlink():
            logger.error(f"Path is a symlink: {path}")
            return False
        
        # Check if path is within base directory
        if base_dir:
            base_dir = Path(base_dir).resolve()
            if not str(path).startswith(str(base_dir)):
                logger.error(f"Path {path} is outside of base directory {base_dir}")
                return False
        
        return True
    except Exception as e:
        logger.error(f"Error validating path {path}: {e}")
        return False


def get_aws_region(region: Optional[str] = None) -> str:
    """
    Get AWS region from provided value, environment, or AWS config.
    
    Args:
        region: Region to use (optional)
        
    Returns:
        AWS region string
    """
    if region:
        return region
    
    # Check environment variables
    if region := os.environ.get("AWS_REGION"):
        return region
    if region := os.environ.get("AWS_DEFAULT_REGION"):
        return region
    
    # Try to get from AWS config
    try:
        result = run_command(["aws", "configure", "get", "region"], check=False)
        if result.success and result.stdout.strip():
            return result.stdout.strip()
    except Exception as e:
        logger.debug(f"Error getting AWS region from config: {e}")
    
    # Default to us-east-1
    logger.warning("Could not determine AWS region. Using default: us-east-1")
    return "us-east-1"


def validate_cidr(cidr: str) -> bool:
    """
    Validate if a string is a valid CIDR notation.
    
    Args:
        cidr: CIDR notation to validate
        
    Returns:
        True if valid, False otherwise
    """
    try:
        ipaddress.ip_network(cidr)
        return True
    except ValueError:
        logger.error(f"Invalid CIDR notation: {cidr}")
        return False


def create_temp_file(content: str, suffix: Optional[str] = None, 
                 mode: int = 0o600, 
                 sensitive: bool = True) -> Tuple[str, callable]:
    """
    Create a temporary file with the given content using secure practices.
    
    Args:
        content: Content to write to the file
        suffix: File extension
        mode: File permissions mode (default: 0o600 - user read/write only)
        sensitive: Whether the file contains sensitive information
        
    Returns:
        Tuple of (file_path, cleanup_function)
    
    Security notes:
        - Creates a private directory with restricted permissions
        - Uses os.open with O_CREAT|O_EXCL to prevent race conditions
        - Sets restrictive permissions before writing any content
        - Provides proper cleanup function
        - Uses urandom for filename uniqueness
    """
    # Create a secure temporary directory with restricted permissions
    temp_dir = tempfile.mkdtemp(prefix="atmos-")
    os.chmod(temp_dir, 0o700)  # Only user can access directory
    
    try:
        # Create a unique filename with sufficient entropy
        random_suffix = os.urandom(16).hex()  # 128 bits of entropy
        file_name = f"tmp-{random_suffix}{suffix or ''}"
        file_path = os.path.join(temp_dir, file_name)
        
        # Create the file securely with proper permissions set from the beginning
        # Using os.open with O_EXCL flag prevents race conditions by ensuring
        # the file doesn't exist before creating it
        fd = os.open(file_path, os.O_CREAT | os.O_WRONLY | os.O_EXCL, mode)
        try:
            # Write content to the file descriptor
            with os.fdopen(fd, 'w') as f:
                f.write(content)
        except Exception as e:
            # Handle any exceptions during write
            os.close(fd)  # Make sure we close the descriptor on error
            raise
            
        # Create a cleanup function that uses a closure to capture the file path
        def cleanup():
            """Remove the temporary directory and its contents securely."""
            try:
                # If file contains sensitive data, overwrite before deletion
                if sensitive and os.path.exists(file_path):
                    # Securely overwrite file with zeros before deletion
                    with open(file_path, 'wb') as f:
                        f.write(b'\0' * len(content.encode('utf-8')))
                # Remove the entire directory structure
                shutil.rmtree(temp_dir, ignore_errors=False)
                logger.debug(f"Temporary directory {temp_dir} cleaned up")
            except Exception as e:
                logger.error(f"Error during secure cleanup: {e}")
    
        # Return the file path and its cleanup function
        return file_path, cleanup
        
    except Exception as e:
        # Clean up the temp directory if anything fails during creation
        shutil.rmtree(temp_dir, ignore_errors=True)
        logger.error(f"Failed to create secure temporary file: {e}")
        raise