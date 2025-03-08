"""
Core operations for Atmos CLI.
Handles component operations like apply, plan, validate, and destroy.
"""

import os
import sys
import json
import time
import concurrent.futures
import subprocess
import shutil
from typing import List, Dict, Any, Optional, Callable
import datetime
from dataclasses import dataclass

from gaia.logger import get_logger
from gaia.config import get_config
from gaia.utils import run_command, CommandResult
from gaia.discovery import discover_and_order_components
from gaia import state

logger = get_logger(__name__)
config = get_config()


@dataclass
class OperationResult:
    """Result of an operation on a component."""
    component: str
    operation: str
    success: bool
    message: str
    exit_code: int
    duration_seconds: float


class ComponentOperation:
    """Base class for component operations."""
    
    def __init__(self, stack: str, parallel: bool = False, continue_on_error: bool = False):
        """Initialize component operation."""
        self.stack = stack
        self.parallel = parallel
        self.continue_on_error = continue_on_error
        
        # Parse stack into tenant, account, environment
        stack_parts = stack.split('-')
        if len(stack_parts) < 3:
            raise ValueError(f"Invalid stack name: {stack}. Expected format: tenant-account-environment")
        
        self.tenant = stack_parts[0]
        self.account = stack_parts[1]
        self.environment = '-'.join(stack_parts[2:])  # Environment might contain hyphens
    
    def run_operation(
        self, 
        operation: str, 
        component: str, 
        args: Optional[List[str]] = None
    ) -> OperationResult:
        """
        Run a Terraform operation on a component.
        
        Args:
            operation: Operation to run (apply, plan, validate, destroy)
            component: Component to run operation on
            args: Additional arguments to pass to atmos terraform command
            
        Returns:
            OperationResult with success/failure and details
        """
        start_time = time.time()
        
        # Check for state locks before destructive operations
        if operation in ['apply', 'destroy', 'import']:
            state.check_state_locks_before_operation(self.stack, operation, component)
        
        # Handle tainting for stateful resources
        if operation == 'apply':
            self._handle_taints(component)
        
        # Prepare command
        cmd = ["atmos", "terraform", operation, component, "-s", self.stack]
        if args:
            cmd.extend(args)
        
        logger.info(f"Running: {' '.join(cmd)}")
        
        try:
            # Define memory limits based on operation type
            # Some operations like plan and apply can use more memory
            memory_limit = None
            if operation in ['plan', 'apply', 'drift']:
                memory_limit = 2048  # 2GB limit for resource-intensive operations
            elif operation in ['validate', 'destroy']:
                memory_limit = 1024  # 1GB limit for medium operations
            else:
                memory_limit = 512   # 512MB limit for other operations
                
            # Special handling for drift detection with detailed exitcode
            if operation == 'drift':
                drift_cmd = ["atmos", "terraform", "plan", component, "-s", self.stack, "-detailed-exitcode"]
                result = run_command(drift_cmd, check=False, memory_limit=memory_limit)
                
                if result.returncode == 0:
                    return OperationResult(
                        component=component,
                        operation=operation,
                        success=True,
                        message="No drift detected",
                        exit_code=0,
                        duration_seconds=time.time() - start_time
                    )
                elif result.returncode == 2:
                    return OperationResult(
                        component=component,
                        operation=operation,
                        success=False,
                        message="Drift detected",
                        exit_code=1,
                        duration_seconds=time.time() - start_time
                    )
                else:
                    return OperationResult(
                        component=component,
                        operation=operation,
                        success=False,
                        message=f"Error during drift detection: {result.stderr}",
                        exit_code=2,
                        duration_seconds=time.time() - start_time
                    )
            
            # For all other operations
            result = run_command(cmd, check=False, memory_limit=memory_limit)
            success = result.returncode == 0
            
            if success:
                # More detailed success message with specific operation information
                if operation == 'apply':
                    message = f"Successfully applied changes to {component}"
                elif operation == 'plan':
                    if 'No changes' in result.stdout:
                        message = f"No changes required for {component}"
                    else:
                        message = f"Successfully planned changes for {component}"
                elif operation == 'validate':
                    message = f"Successfully validated {component}"
                elif operation == 'destroy':
                    message = f"Successfully destroyed {component}"
                elif operation == 'import':
                    message = f"Successfully imported resource into {component}"
                else:
                    message = f"Successfully completed operation '{operation}' on {component}"
            else:
                # Include brief error details in the message for better context
                error_preview = result.stderr.strip().split('\n')[0] if result.stderr else "Unknown error"
                message = f"Failed to {operation} {component}: {error_preview}"
            
            return OperationResult(
                component=component,
                operation=operation,
                success=success,
                message=message,
                exit_code=result.returncode,
                duration_seconds=time.time() - start_time
            )
            
        except Exception as e:
            logger.error(f"Error running {operation} on {component}: {e}")
            
            return OperationResult(
                component=component,
                operation=operation,
                success=False,
                message=f"Error: {str(e)}",
                exit_code=1,
                duration_seconds=time.time() - start_time
            )
    
    def _handle_taints(self, component: str) -> None:
        """Handle tainting for stateful resources."""
        # List of stateful resources that may need tainting
        stateful_resources = {
            "eks": ["aws_eks_cluster.this"],
            "rds": ["aws_db_instance.this"],
            "elasticache": ["aws_elasticache_replication_group.this"],
        }
        
        if component in stateful_resources:
            resources = stateful_resources[component]
            logger.info(f"Checking if {component} resources need to be tainted...")
            
            for resource in resources:
                try:
                    # Attempt to taint if it exists
                    cmd = ["atmos", "terraform", "taint", "-allow-missing", resource, "-s", self.stack]
                    run_command(cmd, check=False, memory_limit=512)  # 512MB for taint operation
                    logger.info(f"Taint check completed for {resource}")
                except Exception as e:
                    logger.debug(f"Failed to check taint for {resource}: {e}")
    
    def process_components(
        self, 
        operation: str, 
        components: List[str], 
        args: Optional[Dict[str, List[str]]] = None
    ) -> Dict[str, OperationResult]:
        """
        Process multiple components with the given operation.
        
        Args:
            operation: Operation to run (apply, plan, validate, destroy)
            components: List of components to process
            args: Dictionary mapping operations to additional arguments
            
        Returns:
            Dictionary mapping component names to operation results
        """
        if not components:
            logger.warning("No components to process")
            return {}
        
        operation_args = args.get(operation, []) if args else []
        
        logger.info(f"Processing {len(components)} components with operation: {operation}")
        logger.info(f"Components to process: {', '.join(components)}")
        
        results: Dict[str, OperationResult] = {}
        
        if self.parallel and len(components) > 1:
            # Process components in parallel
            with concurrent.futures.ThreadPoolExecutor() as executor:
                # Submit all component operations
                future_to_component = {
                    executor.submit(self.run_operation, operation, component, operation_args): component
                    for component in components
                }
                
                # Process results as they complete
                for future in concurrent.futures.as_completed(future_to_component):
                    component = future_to_component[future]
                    try:
                        result = future.result()
                        results[component] = result
                        
                        if not result.success and not self.continue_on_error:
                            # Cancel remaining futures if we shouldn't continue on error
                            for f in future_to_component:
                                if not f.done():
                                    f.cancel()
                            break
                    except Exception as e:
                        logger.error(f"Error processing {component}: {e}")
                        results[component] = OperationResult(
                            component=component,
                            operation=operation,
                            success=False,
                            message=f"Exception: {str(e)}",
                            exit_code=1,
                            duration_seconds=0.0
                        )
        else:
            # Process components sequentially
            for component in components:
                result = self.run_operation(operation, component, operation_args)
                results[component] = result
                
                if not result.success and not self.continue_on_error and operation != 'validate':
                    # For most operations, stop on error unless continue_on_error is True
                    logger.error(f"Component '{component}' failed, stopping processing")
                    break
        
        # Provide a more detailed summary
        success_count = sum(1 for r in results.values() if r.success)
        fail_count = len(results) - success_count
        
        logger.info(f"Operation Summary for '{operation}' on stack '{self.stack}':")
        logger.info(f"Total components processed: {len(components)}")
        logger.info(f"Successfully completed: {success_count}")
        
        if fail_count > 0:
            failed_components = [c for c, r in results.items() if not r.success]
            logger.error(f"Failed components ({fail_count}): {', '.join(failed_components)}")
            
            # Add error details for each failed component for better troubleshooting
            for component, result in results.items():
                if not result.success:
                    error_msg = result.message.replace("Failed to ", "").strip()
                    logger.error(f"  - {component}: {error_msg}")
        else:
            logger.info(f"✅ All {len(components)} components processed successfully")
        
        return results


def apply_components(
    stack: str, 
    auto_approve: bool = False, 
    components: Optional[List[str]] = None,
    parallel: bool = False
) -> Dict[str, OperationResult]:
    """
    Apply Terraform components for a stack.
    
    Args:
        stack: The stack to apply components for
        auto_approve: Whether to auto-approve apply operations
        components: Specific components to apply (if None, all components will be applied)
        parallel: Whether to apply components in parallel
        
    Returns:
        Dictionary mapping component names to operation results
    """
    logger.info(f"Applying components for stack: {stack}")
    
    operation = ComponentOperation(stack, parallel=parallel)
    
    # Get components in correct order if not specified
    if not components:
        components = discover_and_order_components(stack)
    
    # Set up args with auto-approve if requested
    args = {}
    if auto_approve:
        args["apply"] = ["-auto-approve"]
    
    return operation.process_components("apply", components, args)


def plan_components(
    stack: str,
    output_dir: Optional[str] = None,
    components: Optional[List[str]] = None,
    parallel: bool = False
) -> Dict[str, OperationResult]:
    """
    Plan Terraform components for a stack.
    
    Args:
        stack: The stack to plan components for
        output_dir: Directory to save plan files
        components: Specific components to plan (if None, all components will be planned)
        parallel: Whether to plan components in parallel
        
    Returns:
        Dictionary mapping component names to operation results
    """
    logger.info(f"Planning components for stack: {stack}")
    
    operation = ComponentOperation(stack, parallel=parallel)
    
    # Get components in correct order if not specified
    if not components:
        components = discover_and_order_components(stack)
    
    # Set up args with output file if specified
    args = {}
    if output_dir:
        # Create output directory if needed
        os.makedirs(output_dir, exist_ok=True)
        
        # Create args for each component with its own output file
        args["plan"] = []
        for component in components:
            args["plan"].append(f"--out={os.path.join(output_dir, f'{component}.tfplan')}")
    
    return operation.process_components("plan", components, args)


def validate_components(
    stack: str,
    components: Optional[List[str]] = None,
    parallel: bool = False
) -> Dict[str, OperationResult]:
    """
    Validate Terraform components for a stack.
    
    Args:
        stack: The stack to validate components for
        components: Specific components to validate (if None, all components will be validated)
        parallel: Whether to validate components in parallel
        
    Returns:
        Dictionary mapping component names to operation results
    """
    logger.info(f"Validating components for stack: {stack}")
    
    # For validation, always continue on error
    operation = ComponentOperation(stack, parallel=parallel, continue_on_error=True)
    
    # Get components in correct order if not specified
    if not components:
        components = discover_and_order_components(stack)
    
    return operation.process_components("validate", components)


def destroy_components(
    stack: str,
    auto_approve: bool = False,
    safe_destroy: bool = False,
    components: Optional[List[str]] = None,
) -> Dict[str, OperationResult]:
    """
    Destroy Terraform components for a stack.
    
    Args:
        stack: The stack to destroy components for
        auto_approve: Whether to auto-approve destroy operations
        safe_destroy: Whether to prompt for confirmation if a component fails
        components: Specific components to destroy (if None, all components will be destroyed)
        
    Returns:
        Dictionary mapping component names to operation results
    """
    logger.info(f"Destroying components for stack: {stack}")
    
    # Config for destroy - can't use parallel due to dependency order
    operation = ComponentOperation(stack, continue_on_error=not safe_destroy)
    
    # Get components in reverse order if not specified
    if not components:
        components = discover_and_order_components(stack, reverse=True)
    
    # Set up args with auto-approve if requested
    args = {}
    if auto_approve:
        args["destroy"] = ["-auto-approve"]
    
    logger.info(f"Stack: {stack}")
    logger.info(f"Components to destroy: {len(components)}")
    
    if safe_destroy:
        logger.info("Safe destroy mode enabled: Will prompt for confirmation if any component fails")
    else:
        logger.warning("Safe destroy mode disabled: Will continue with remaining components even if some fail")
    
    results: Dict[str, OperationResult] = {}
    remaining_count = len(components)
    
    # Process components one by one with special handling
    for i, component in enumerate(components):
        processed_count = i + 1
        remaining_count -= 1
        
        logger.info(f"Processing component {processed_count}/{len(components)}: {component}")
        
        result = operation.run_operation("destroy", component, args.get("destroy"))
        results[component] = result
        
        if not result.success:
            logger.error(f"Component {component} failed to destroy. Remaining components: {remaining_count}")
            
            if safe_destroy and sys.stdout.isatty():
                # Only prompt in interactive mode with safe destroy
                logger.warning("Continuing may leave your environment in an inconsistent state if components have dependencies")
                
                while True:
                    response = input("Continue with destroying remaining components? (y/n): ").strip().lower()
                    if response in ['y', 'n']:
                        break
                    print("Please enter 'y' or 'n'")
                
                if response != 'y':
                    logger.warning(f"Destroy operation aborted by user after {processed_count}/{len(components)} components")
                    break
            elif safe_destroy:
                # In non-interactive mode with safe destroy, stop on failure
                logger.error("Non-interactive mode with safe_destroy=True: Aborting remaining destroys")
                break
            else:
                logger.warning(f"Component {component} failed to destroy. Continuing with next component")
    
    # Provide summary
    success_count = sum(1 for r in results.values() if r.success)
    fail_count = len(results) - success_count
    
    logger.info("Destroy Summary")
    logger.info(f"Components processed: {len(results)}/{len(components)}")
    
    if fail_count > 0:
        failed_components = [c for c, r in results.items() if not r.success]
        logger.warning(f"Failed components: {fail_count} - {', '.join(failed_components)}")
    else:
        logger.info("All components successfully destroyed")
    
    return results


def detect_drift(
    stack: str,
    components: Optional[List[str]] = None,
    parallel: bool = False
) -> Dict[str, Any]:
    """
    Detect drift in Terraform components for a stack.
    
    Args:
        stack: The stack to detect drift for
        components: Specific components to check (if None, all components will be checked)
        parallel: Whether to check components in parallel
        
    Returns:
        Drift report as a dictionary
    """
    logger.info(f"Detecting drift for stack: {stack}")
    
    # For drift detection, always continue on error
    operation = ComponentOperation(stack, parallel=parallel, continue_on_error=True)
    
    # Get components in correct order if not specified
    if not components:
        components = discover_and_order_components(stack)
    
    # Parse stack parts
    stack_parts = stack.split('-')
    tenant = stack_parts[0]
    account = stack_parts[1]
    environment = '-'.join(stack_parts[2:])  # Environment might contain hyphens
    
    # Create timestamp for report
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    
    # Define drift logs directory
    logs_dir = os.path.join("logs", "drift")
    os.makedirs(logs_dir, exist_ok=True)
    
    report_file = os.path.join(logs_dir, f"drift-report-{tenant}-{account}-{environment}-{timestamp}.json")
    
    logger.info(f"Storing drift report in: {report_file}")
    
    # Initialize drift report
    drift_report = {
        "report_id": timestamp,
        "stack": stack,
        "tenant": tenant,
        "account": account,
        "environment": environment,
        "detected_at": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "components": {},
        "summary": {
            "total_components": len(components),
            "drifted_components": 0,
            "drift_detected": False
        }
    }
    
    # Process all components
    drift_detected = False
    drift_components = []
    
    # Process components to check drift
    results = operation.process_components("drift", components)
    
    # Process results into report
    for component, result in results.items():
        component_status = "unknown"
        component_error = ""
        component_details = ""
        
        if result.success:
            component_status = "no_drift"
        elif result.exit_code == 1:
            component_status = "drifted"
            drift_detected = True
            drift_components.append(component)
            component_details = result.message
        else:
            component_status = "error"
            component_error = result.message
        
        drift_report["components"][component] = {
            "status": component_status,
            "error": component_error,
            "details": component_details
        }
    
    # Update summary
    drift_report["summary"]["drifted_components"] = len(drift_components)
    drift_report["summary"]["drift_detected"] = drift_detected
    
    # Save report to file
    with open(report_file, 'w') as f:
        json.dump(drift_report, f, indent=2)
    
    # Create human-readable summary file if drift detected
    if drift_detected:
        logger.warning(f"Drift detected in the following components: {', '.join(drift_components)}")
        logger.info(f"Detailed drift report saved to: {report_file}")
        
        summary_file = os.path.join(logs_dir, f"drift-summary-{tenant}-{account}-{environment}-{timestamp}.txt")
        
        with open(summary_file, 'w') as f:
            f.write("DRIFT DETECTION SUMMARY\n")
            f.write("========================\n")
            f.write(f"Stack: {stack}\n")
            f.write(f"Environment: {tenant}-{account}-{environment}\n")
            f.write(f"Timestamp: {datetime.datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}\n")
            f.write("========================\n\n")
            f.write("DRIFTED COMPONENTS:\n")
            
            for comp in drift_components:
                f.write(f"- {comp}\n")
            
            f.write("\n")
            f.write(f"Run 'atmos terraform plan <component> -s {stack}' for details on each drifted component.\n\n")
            f.write(f"Full JSON report: {report_file}\n")
        
        logger.info(f"Human-readable summary saved to: {summary_file}")
    else:
        logger.info("No drift detected in any components")
    
    return drift_report


def run_operation(
    operation: str,
    stack: str,
    auto_approve: bool = False,
    safe_destroy: bool = False,
    output_dir: Optional[str] = None,
    components: Optional[List[str]] = None,
    parallel: bool = False,
    reverse: bool = False
) -> Dict[str, Any]:
    """
    Run an operation on components in a stack.
    
    Args:
        operation: Operation to run (apply, plan, validate, destroy, drift)
        stack: Stack to run operation on
        auto_approve: Whether to auto-approve apply/destroy operations
        safe_destroy: Whether to prompt for confirmation on destroy failures
        output_dir: Directory to save plan output (for plan operation)
        components: Specific components to operate on
        parallel: Whether to process components in parallel
        reverse: Whether to process components in reverse dependency order
        
    Returns:
        Dictionary with operation results
    """
    logger.info(f"Starting operation: {operation}")
    
    # Use stack environment variables if provided
    if not stack and os.environ.get("tenant") and os.environ.get("account") and os.environ.get("environment"):
        tenant = os.environ.get("tenant")
        account = os.environ.get("account")
        environment = os.environ.get("environment")
        stack = f"{tenant}-{account}-{environment}"
        logger.info(f"Using stack name from environment variables: {stack}")
    
    if not stack:
        logger.error("Stack name is required")
        return {"error": "Stack name is required"}
    
    # Discover and order components if not provided
    if not components:
        logger.info("Discovering components...")
        components = discover_and_order_components(stack, reverse)
        if not components:
            logger.error("Failed to discover components")
            return {"error": "Failed to discover components"}
    
    # Run the appropriate operation
    try:
        if operation == "apply":
            results = apply_components(stack, auto_approve, components, parallel)
        elif operation == "plan":
            results = plan_components(stack, output_dir, components, parallel)
        elif operation == "validate":
            results = validate_components(stack, components, parallel)
        elif operation == "destroy":
            results = destroy_components(stack, auto_approve, safe_destroy, components)
        elif operation == "drift":
            results = detect_drift(stack, components, parallel)
        else:
            logger.error(f"Unknown operation: {operation}")
            return {"error": f"Unknown operation: {operation}"}
        
        logger.info(f"Operation {operation} completed")
        return {"results": results, "operation": operation, "stack": stack}
        
    except Exception as e:
        logger.error(f"Error during {operation} operation: {e}")
        return {"error": str(e), "operation": operation, "stack": stack}


class LintOperation:
    """
    Linting operation for Terraform code and configuration files.
    Performs:
    - Terraform formatting
    - YAML linting
    - Security scanning
    """

    def __init__(self, config: Dict[str, Any]):
        """Initialize LintOperation."""
        self.config = config
        self.logger = get_logger(__name__)
        self.terraform_path = "./components/terraform"

    def terraform_format(self, fix: bool = False) -> bool:
        """Run Terraform format check or fix."""
        self.logger.info("Running Terraform format check...")
        
        cmd = ["terraform", "fmt", "-recursive", self.terraform_path]
        if not fix:
            cmd.insert(2, "-check")
        
        result = run_command(cmd)
        if result.returncode != 0:
            self.logger.error("❌ Terraform formatting issues found.")
            if not fix:
                self.logger.info("Run 'gaia workflow lint --fix' to fix formatting issues.")
            return False
        
        self.logger.info("✅ Terraform formatting check passed")
        return True

    def yaml_lint(self) -> bool:
        """Run YAML linting if yamllint is available."""
        # Check if yamllint is available
        if not shutil.which("yamllint"):
            self.logger.info("⚠️ yamllint not found, skipping YAML linting")
            return True
        
        self.logger.info("Running YAML linting...")
        
        # Determine yamllint config
        yamllint_args = []
        if os.path.isfile(".yamllint.yml"):
            yamllint_args = ["-c", ".yamllint.yml"]
        else:
            # Default config with 120 char line length
            yamllint_args = ["-d", "{extends: default, rules: {line-length: {max: 120}}}"]
        
        cmd = ["yamllint"] + yamllint_args + ["."]
        result = run_command(cmd)
        
        if result.returncode != 0:
            self.logger.error("❌ YAML lint issues found")
            return False
        
        self.logger.info("✅ YAML lint check passed")
        return True

    def security_scan(self) -> bool:
        """Run security scanning with tfsec if available."""
        # Check if tfsec is available
        if not shutil.which("tfsec"):
            self.logger.info("⚠️ tfsec not found, skipping security scanning")
            return True
        
        self.logger.info("Running security scan...")
        
        cmd = ["tfsec", "./components/terraform", "--soft-fail", "--concise-output"]
        result = run_command(cmd)
        
        if result.returncode != 0:
            self.logger.error("⚠️ Security issues found in Terraform code")
            return False
        
        self.logger.info("✅ Security scan passed")
        return True

    def execute(self, fix: bool = False, skip_security: bool = False) -> bool:
        """Execute all linting operations."""
        # Run Terraform format
        if not self.terraform_format(fix):
            return False
        
        # Run YAML linting
        if not self.yaml_lint():
            return False
        
        # Run security scanning (optional)
        if not skip_security and not self.security_scan():
            return False
        
        self.logger.info("All lint checks passed successfully!")
        return True


def lint_code(fix: bool = False, skip_security: bool = False) -> Dict[str, Any]:
    """
    Lint Terraform code and configuration files.
    
    Args:
        fix: Whether to automatically fix issues
        skip_security: Whether to skip security scanning
        
    Returns:
        Dictionary with lint results
    """
    logger.info("Starting lint operation")
    
    try:
        operation = LintOperation(config)
        success = operation.execute(fix=fix, skip_security=skip_security)
        
        if success:
            return {"success": True, "message": "All lint checks passed successfully!"}
        else:
            return {"success": False, "message": "Lint checks failed"}
            
    except Exception as e:
        logger.error(f"Error during lint operation: {e}")
        return {"success": False, "error": str(e)}


class ImportOperation:
    """
    Import existing resources into Terraform state.
    """
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize ImportOperation."""
        self.config = config
        self.logger = get_logger(__name__)
    
    def execute(
        self, 
        resource_address: str,
        resource_id: str,
        component: str,
        stack: str
    ) -> Dict[str, Any]:
        """
        Import an existing resource into Terraform state.
        
        Args:
            resource_address: The Terraform resource address (e.g., aws_s3_bucket.bucket)
            resource_id: The resource ID (e.g., my-bucket-name)
            component: The component to import the resource into
            stack: The stack to import the resource into
            
        Returns:
            Dictionary with import results
        """
        self.logger.info(f"Importing resource {resource_id} as {resource_address} into {component} in stack {stack}")
        
        # Validate inputs
        if not resource_address:
            return {"success": False, "error": "Resource address is required"}
        
        if not resource_id:
            return {"success": False, "error": "Resource ID is required"}
        
        if not component:
            return {"success": False, "error": "Component is required"}
        
        if not stack:
            return {"success": False, "error": "Stack is required"}
        
        # Check for state locks before import operation
        state.check_state_locks_before_operation(stack, "import", component)
        
        # Prepare and run the import command
        cmd = ["atmos", "terraform", "import", component, resource_address, resource_id, "-s", stack]
        
        try:
            result = run_command(cmd)
            
            if result.returncode == 0:
                self.logger.info(f"Successfully imported {resource_id} as {resource_address}")
                return {
                    "success": True,
                    "message": f"Successfully imported {resource_id} as {resource_address}",
                    "component": component,
                    "stack": stack
                }
            else:
                self.logger.error(f"Failed to import resource: {result.stderr}")
                return {
                    "success": False, 
                    "error": f"Import failed: {result.stderr}",
                    "component": component,
                    "stack": stack
                }
                
        except Exception as e:
            self.logger.error(f"Error during import operation: {e}")
            return {"success": False, "error": str(e)}


def import_resource(
    resource_address: str,
    resource_id: str,
    component: str,
    stack: str
) -> Dict[str, Any]:
    """
    Import an existing resource into Terraform state.
    
    Args:
        resource_address: The Terraform resource address (e.g., aws_s3_bucket.bucket)
        resource_id: The resource ID (e.g., my-bucket-name)
        component: The component to import the resource into
        stack: The stack to import the resource into
        
    Returns:
        Dictionary with import results
    """
    logger.info(f"Starting import operation for {resource_id} as {resource_address}")
    
    try:
        operation = ImportOperation(config)
        return operation.execute(
            resource_address=resource_address,
            resource_id=resource_id,
            component=component,
            stack=stack
        )
    except Exception as e:
        logger.error(f"Error during import operation: {e}")
        return {"success": False, "error": str(e)}


class ValidationOperation:
    """
    Validate Terraform components in a specified tenant/account/environment.
    """
    
    def __init__(self, config: Dict[str, Any]):
        """Initialize ValidationOperation."""
        self.config = config
        self.logger = get_logger(__name__)
    
    def execute(
        self, 
        tenant: str,
        account: str,
        environment: str,
        parallel: bool = True,
        components: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """
        Validate Terraform components in a tenant/account/environment.
        
        Args:
            tenant: The tenant name
            account: The account name
            environment: The environment name
            parallel: Whether to run validations in parallel
            components: Specific components to validate (if None, all components will be validated)
            
        Returns:
            Dictionary with validation results
        """
        self.logger.info(f"Validating components for {tenant}/{account}/{environment}")
        
        # Construct the stack name
        stack = f"{tenant}-{account}-{environment}"
        
        # First run linting to check formatting
        lint_result = lint_code(fix=False, skip_security=False)
        if not lint_result.get("success", False):
            self.logger.error("Linting failed. Fix formatting issues before validating.")
            return {
                "success": False, 
                "error": "Linting failed. Run 'gaia workflow lint --fix' to fix formatting issues."
            }
        
        # Get components in correct order if not specified
        if not components:
            try:
                components = discover_and_order_components(stack)
            except Exception as e:
                self.logger.error(f"Error discovering components: {e}")
                return {"success": False, "error": f"Error discovering components: {str(e)}"}
            
        # Create validation operation
        operation = ComponentOperation(stack, parallel=parallel, continue_on_error=True)
        
        # Validate all components
        results = operation.process_components("validate", components)
        
        # Check if all validations succeeded
        all_success = all(result.success for result in results.values())
        
        if all_success:
            self.logger.info(f"All {len(results)} components validated successfully")
            return {
                "success": True,
                "message": f"All {len(results)} components validated successfully",
                "components": len(results),
                "results": results
            }
        else:
            failed_components = [name for name, result in results.items() if not result.success]
            self.logger.error(f"Validation failed for {len(failed_components)} components: {', '.join(failed_components)}")
            return {
                "success": False,
                "error": f"Validation failed for {len(failed_components)} components: {', '.join(failed_components)}",
                "components": len(results),
                "failed": len(failed_components),
                "failed_components": failed_components,
                "results": results
            }


def validate_components(
    tenant: str,
    account: str,
    environment: str,
    parallel: bool = True,
    components: Optional[List[str]] = None
) -> Dict[str, Any]:
    """
    Validate Terraform components in a specified tenant/account/environment.
    
    Args:
        tenant: The tenant name
        account: The account name
        environment: The environment name
        parallel: Whether to run validations in parallel
        components: Specific components to validate (if None, all components will be validated)
        
    Returns:
        Dictionary with validation results
    """
    logger.info(f"Starting validation for {tenant}/{account}/{environment}")
    
    try:
        operation = ValidationOperation(config)
        return operation.execute(
            tenant=tenant,
            account=account,
            environment=environment,
            parallel=parallel,
            components=components
        )
    except Exception as e:
        logger.error(f"Error during validation: {e}")
        return {"success": False, "error": str(e)}