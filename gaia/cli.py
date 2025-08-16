#!/usr/bin/env python3
"""
Gaia CLI - Enhanced developer experience wrapper for Atmos operations

Provides user-friendly commands, better error handling, and helpful context
for working with Terraform/Atmos infrastructure.
"""

import subprocess
import sys
import typer
import os
import json
import re
from typing import List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime

# Enhanced CLI app with rich help
app = typer.Typer(
    help="🌍 Gaia CLI - Enhanced developer experience for Atmos operations",
    rich_markup_mode="rich",
    add_completion=False
)

def run_atmos_command(command: List[str], check: bool = True, capture_output: bool = False) -> subprocess.CompletedProcess:
    """Run an atmos command with enhanced error handling and user feedback"""
    full_command = ["atmos"] + command
    
    # Show user-friendly command representation
    friendly_command = format_command_for_display(command)
    typer.echo(f"🚀 {friendly_command}")
    
    try:
        # Check if atmos is available first
        if not is_atmos_available():
            show_atmos_installation_help()
            sys.exit(1)
            
        # Check if we're in a valid atmos project
        if not is_in_atmos_project():
            typer.echo("❌ Not in an Atmos project directory. Please run from the project root.", err=True)
            typer.echo("💡 Look for 'atmos.yaml' file in the current or parent directories.", err=True)
            sys.exit(1)
        
        result = subprocess.run(
            full_command,
            capture_output=capture_output,
            check=check,
            text=True if capture_output else None
        )
        
        if result.returncode == 0 and not capture_output:
            typer.echo("✅ Command completed successfully")
        
        return result
        
    except subprocess.CalledProcessError as e:
        handle_atmos_error(e, command)
    except FileNotFoundError:
        show_atmos_installation_help()
        sys.exit(1)
    except KeyboardInterrupt:
        typer.echo("\n⏹️  Operation cancelled by user", err=True)
        sys.exit(130)

def format_command_for_display(command: List[str]) -> str:
    """Format command for user-friendly display"""
    if not command:
        return "atmos"
    
    # Convert complex stack names to friendly names    
    cmd_str = " ".join(command)
    
    # Replace complex stack patterns with friendly names
    stack_pattern = r'orgs/([^/]+)/([^/]+)/([^/]+)/([^/\s]+)'
    friendly_stack = lambda m: f"{m.group(1)}-{m.group(4)}-{m.group(2)}"
    cmd_str = re.sub(stack_pattern, friendly_stack, cmd_str)
    
    return f"atmos {cmd_str}"

def is_atmos_available() -> bool:
    """Check if atmos command is available"""
    try:
        subprocess.run(["atmos", "version"], capture_output=True, check=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
        return False

def is_in_atmos_project() -> bool:
    """Check if we're in a valid Atmos project directory"""
    current_dir = Path.cwd()
    
    # Check current directory and parents for atmos.yaml
    for directory in [current_dir] + list(current_dir.parents):
        if (directory / "atmos.yaml").exists():
            return True
    
    return False

def show_atmos_installation_help():
    """Show helpful installation instructions for Atmos"""
    typer.echo("❌ Atmos command not found!", err=True)
    typer.echo("")
    typer.echo("🛠️  To install Atmos:", err=True)
    typer.echo("   macOS: brew install cloudposse/tap/atmos", err=True)
    typer.echo("   Linux: Visit https://atmos.tools/install", err=True)
    typer.echo("")
    typer.echo("💡 After installation, run 'atmos version' to verify.", err=True)

def handle_atmos_error(error: subprocess.CalledProcessError, command: List[str]):
    """Handle Atmos command errors with helpful messages"""
    typer.echo(f"❌ Command failed with exit code {error.returncode}", err=True)
    
    # Provide context-specific help based on the command
    if len(command) >= 2:
        cmd_type = command[0]
        sub_command = command[1] if len(command) > 1 else ""
        
        if cmd_type == "terraform" and "plan" in sub_command:
            typer.echo("💡 Common plan failures:", err=True)
            typer.echo("   • Check AWS credentials: aws sts get-caller-identity", err=True)
            typer.echo("   • Verify stack configuration exists", err=True)
            typer.echo("   • Run 'make validate' to check configuration", err=True)
            
        elif cmd_type == "workflow":
            typer.echo("💡 Workflow troubleshooting:", err=True)
            typer.echo("   • Check if all required parameters are provided", err=True)
            typer.echo("   • Verify stack exists: make list-stacks", err=True)
            typer.echo("   • Check logs in the 'logs/' directory", err=True)
    
    typer.echo("")
    typer.echo("🔍 For detailed troubleshooting, run: make doctor", err=True)
    sys.exit(error.returncode)

def get_available_stacks() -> List[str]:
    """Get list of available stacks from Atmos"""
    try:
        result = run_atmos_command(["list", "stacks"], capture_output=True)
        if result.stdout:
            return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    except:
        pass
    return []

def get_stack_components(stack: str) -> List[str]:
    """Get components available for a specific stack"""
    try:
        result = run_atmos_command(["list", "components", "-s", stack], capture_output=True)
        if result.stdout:
            return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
    except:
        pass
    return []

# Workflow Commands
workflow_app = typer.Typer(help="Workflow operations")
app.add_typer(workflow_app, name="workflow")

@workflow_app.command("plan-environment")
def plan_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name (e.g., fnx)"),
    account: str = typer.Option(..., "--account", "-a", help="Account name (e.g., dev)"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name (e.g., testenv-01)"),
):
    """📋 Plan changes for all components in an environment"""
    friendly_name = f"{tenant}-{environment}-{account}"
    typer.echo(f"🎯 Planning environment: {friendly_name}")
    
    run_atmos_command([
        "workflow", "plan-environment",
        f"tenant={tenant}",
        f"account={account}",
        f"environment={environment}"
    ])

@workflow_app.command("apply-environment")
def apply_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name (e.g., fnx)"),
    account: str = typer.Option(..., "--account", "-a", help="Account name (e.g., dev)"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name (e.g., testenv-01)"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Skip confirmation prompt"),
):
    """🚀 Apply changes for all components in an environment"""
    friendly_name = f"{tenant}-{environment}-{account}"
    
    if not auto_approve:
        typer.echo(f"⚠️  This will apply changes to environment: {friendly_name}")
        confirm = typer.confirm("Are you sure you want to continue?")
        if not confirm:
            typer.echo("❌ Apply cancelled")
            return
    
    typer.echo(f"🚀 Applying changes to environment: {friendly_name}")
    
    run_atmos_command([
        "workflow", "apply-environment",
        f"tenant={tenant}",
        f"account={account}",
        f"environment={environment}"
    ])

@workflow_app.command("validate")
def validate(
    tenant: Optional[str] = typer.Option(None, "--tenant", "-t", help="Tenant name (optional - validates all if not specified)"),
    account: Optional[str] = typer.Option(None, "--account", "-a", help="Account name (optional)"),
    environment: Optional[str] = typer.Option(None, "--environment", "-e", help="Environment name (optional)"),
):
    """✅ Validate Terraform configurations"""
    
    if tenant and account and environment:
        friendly_name = f"{tenant}-{environment}-{account}"
        typer.echo(f"🔍 Validating environment: {friendly_name}")
        run_atmos_command([
            "workflow", "validate",
            f"tenant={tenant}",
            f"account={account}",
            f"environment={environment}"
        ])
    else:
        typer.echo("🔍 Validating all configurations...")
        run_atmos_command(["workflow", "validate"])

@workflow_app.command("lint")
def lint(
    fix: bool = typer.Option(False, "--fix", help="Automatically fix formatting issues"),
):
    """🧹 Lint and format code"""
    typer.echo("🧹 Linting and formatting code...")
    
    cmd = ["workflow", "lint"]
    if fix:
        cmd.append("fix=true")
        typer.echo("🔧 Auto-fix enabled")
    
    run_atmos_command(cmd)

@workflow_app.command("drift-detection")
def drift_detection():
    """🔍 Check for configuration drift"""
    typer.echo("🔍 Checking for configuration drift...")
    typer.echo("💡 This compares current state with desired configuration")
    run_atmos_command(["workflow", "drift-detection"])

@workflow_app.command("onboard-environment")
def onboard_environment(
    tenant: str = typer.Option(..., "--tenant", "-t", help="Tenant name (e.g., fnx)"),
    account: str = typer.Option(..., "--account", "-a", help="Account name (e.g., dev)"),
    environment: str = typer.Option(..., "--environment", "-e", help="Environment name (e.g., testenv-02)"),
    vpc_cidr: str = typer.Option("10.0.0.0/16", "--vpc-cidr", help="VPC CIDR block (default: 10.0.0.0/16)"),
):
    """🏗️  Onboard a new environment with all required infrastructure"""
    friendly_name = f"{tenant}-{environment}-{account}"
    
    typer.echo(f"🏗️  Onboarding new environment: {friendly_name}")
    typer.echo(f"🌐 VPC CIDR: {vpc_cidr}")
    
    # Validate CIDR format
    import ipaddress
    try:
        ipaddress.IPv4Network(vpc_cidr, strict=False)
    except ValueError:
        typer.echo(f"❌ Invalid VPC CIDR format: {vpc_cidr}", err=True)
        typer.echo("💡 Example: 10.1.0.0/16", err=True)
        sys.exit(1)
    
    typer.echo("ℹ️  This will create:") 
    typer.echo("   • VPC with public/private subnets")
    typer.echo("   • Security groups")
    typer.echo("   • IAM roles and policies")
    typer.echo("   • Backend state configuration")
    
    if not typer.confirm("Continue with onboarding?"):
        typer.echo("❌ Onboarding cancelled")
        return
    
    run_atmos_command([
        "workflow", "onboard-environment",
        f"tenant={tenant}",
        f"account={account}",
        f"environment={environment}",
        f"vpc_cidr={vpc_cidr}"
    ])

# Direct Terraform Commands
terraform_app = typer.Typer(help="Direct Terraform operations")
app.add_typer(terraform_app, name="terraform")

@terraform_app.command("plan")
def terraform_plan(
    component: str = typer.Argument(help="Component name"),
    stack: str = typer.Option(..., "--stack", "-s", help="Stack name"),
):
    """Run terraform plan for a component"""
    run_atmos_command(["terraform", "plan", component, "-s", stack])

@terraform_app.command("apply")
def terraform_apply(
    component: str = typer.Argument(help="Component name"),
    stack: str = typer.Option(..., "--stack", "-s", help="Stack name"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Auto approve changes"),
):
    """Run terraform apply for a component"""
    cmd = ["terraform", "apply", component, "-s", stack]
    if auto_approve:
        cmd.append("--auto-approve")
    run_atmos_command(cmd)

@terraform_app.command("validate")
def terraform_validate(
    component: str = typer.Argument(help="Component name"),
    stack: str = typer.Option(..., "--stack", "-s", help="Stack name"),
):
    """Run terraform validate for a component"""
    run_atmos_command(["terraform", "validate", component, "-s", stack])

@terraform_app.command("destroy")
def terraform_destroy(
    component: str = typer.Argument(help="Component name"),
    stack: str = typer.Option(..., "--stack", "-s", help="Stack name"),
    auto_approve: bool = typer.Option(False, "--auto-approve", help="Auto approve destruction"),
):
    """Run terraform destroy for a component"""
    cmd = ["terraform", "destroy", component, "-s", stack]
    if auto_approve:
        cmd.append("--auto-approve")
    run_atmos_command(cmd)

# Utility Commands
@app.command("describe")
def describe(
    what: str = typer.Argument(help="What to describe (stacks, component)"),
    component: Optional[str] = typer.Option(None, "--component", "-c", help="Component name"),
    stack: Optional[str] = typer.Option(None, "--stack", "-s", help="Stack name"),
):
    """📖 Describe stacks or components with detailed information"""
    
    if what == "stacks" and not stack:
        typer.echo("📋 Available stacks:")
        stacks = get_available_stacks()
        for stack in stacks:
            # Convert to friendly name for display
            friendly = re.sub(r'orgs/([^/]+)/([^/]+)/([^/]+)/([^/\s]+)', r'\1-\4-\2', stack)
            typer.echo(f"   • {friendly} ({stack})")
        return
    
    cmd = ["describe", what]
    if component:
        cmd.append(component)
    if stack:
        cmd.extend(["-s", stack])
    run_atmos_command(cmd)

@app.command("list")
def list_cmd(
    what: str = typer.Argument(help="What to list (stacks, components)"),
    stack: Optional[str] = typer.Option(None, "--stack", "-s", help="Stack name (for listing components)"),
):
    """📋 List stacks or components"""
    
    if what == "stacks":
        typer.echo("📋 Available stacks:")
        stacks = get_available_stacks()
        for stack in stacks:
            # Convert to friendly name for display
            friendly = re.sub(r'orgs/([^/]+)/([^/]+)/([^/]+)/([^/\s]+)', r'\1-\4-\2', stack)
            typer.echo(f"   • {friendly}")
    elif what == "components":
        if stack:
            typer.echo(f"📦 Components in stack {stack}:")
            components = get_stack_components(stack)
            for component in components:
                typer.echo(f"   • {component}")
        else:
            typer.echo("💡 Use --stack to specify which stack's components to list")
            typer.echo("📋 Available stacks:")
            stacks = get_available_stacks()
            for stack in stacks[:3]:  # Show first 3 as examples
                friendly = re.sub(r'orgs/([^/]+)/([^/]+)/([^/]+)/([^/\s]+)', r'\1-\4-\2', stack)
                typer.echo(f"   • {friendly}")
            if len(stacks) > 3:
                typer.echo(f"   ... and {len(stacks) - 3} more")
    else:
        run_atmos_command(["list", what])

@app.command("version")
def version():
    """📋 Show version information for Gaia and Atmos"""
    from . import __version__, __author__
    
    typer.echo(f"🌍 Gaia CLI {__version__}")
    typer.echo(f"👥 {__author__}")
    typer.echo("")
    typer.echo("📦 Atmos version:")
    
    if is_atmos_available():
        run_atmos_command(["version"])
    else:
        typer.echo("❌ Atmos not found - please install from https://atmos.tools/install")

# =============================================================================
# Unified Task Orchestration Commands
# =============================================================================

from .control_plane import control_plane
from .task_orchestrator import orchestrator, TaskPriority

@app.command("smart")
def smart_interface(
    query: str = typer.Argument(help="Natural language query describing what you want to do"),
    execute: bool = typer.Option(False, "--execute", "-x", help="Execute the best suggestion automatically"),
    learn: bool = typer.Option(False, "--learn", "-l", help="Learn from this interaction")
):
    """🧠 Intelligent command interface - describe what you want in natural language"""
    
    # Import control plane functionality
    from .control_plane import app as control_app
    control_app.commands["smart"](query, execute, 3)

@app.command("orchestrate") 
def orchestrate_tasks(
    tasks: List[str] = typer.Option([], "--task", "-t", help="Specific tasks to run (can be repeated)"),
    environment: str = typer.Option("", "--environment", "-e", help="Target environment (tenant-account-env)"),
    parallel: bool = typer.Option(True, "--parallel/--sequential", help="Run tasks in parallel when possible"),
    plan_only: bool = typer.Option(False, "--plan-only", help="Show execution plan without running")
):
    """🎼 Orchestrate multiple tasks with intelligent dependency resolution"""
    
    typer.echo(f"🎼 Task Orchestration")
    
    # Parse environment if provided
    if environment:
        parts = environment.split('-')
        if len(parts) >= 3:
            tenant, env_name, account = parts[0], parts[1], parts[2]
            orchestrator.define_environment_tasks(tenant, account, env_name)
    
    # Default task set if none specified
    if not tasks:
        tasks = ["validate-structure", "check-tools", "lint-terraform", "validate-atmos"]
        if environment:
            tasks.append(f"validate-{environment}")
    
    try:
        execution_plan = orchestrator.get_execution_plan(tasks)
        
        typer.echo("📋 Execution Plan:")
        for layer_num, layer in enumerate(execution_plan, 1):
            typer.echo(f"  Layer {layer_num}: {', '.join(layer)}")
        
        if plan_only:
            typer.echo("✅ Plan generated (use --no-plan-only to execute)")
            return
        
        typer.echo("\n🚀 Starting execution...")
        
        # Use asyncio for task execution
        import asyncio
        results = asyncio.run(orchestrator.execute_tasks(tasks, parallel))
        
        # Show results
        successful = sum(results.values())
        total = len(results)
        
        if successful == total:
            typer.echo(f"✅ All {total} tasks completed successfully!")
        else:
            failed = total - successful
            typer.echo(f"⚠️  {successful}/{total} tasks succeeded, {failed} failed")
            
        # Show detailed report
        report = orchestrator.get_task_report()
        if report['failed_tasks']:
            typer.echo("\n❌ Failed tasks:")
            for failed in report['failed_tasks']:
                typer.echo(f"  • {failed['name']}: {failed['error']}")
    
    except Exception as e:
        typer.echo(f"❌ Orchestration failed: {e}", err=True)
        sys.exit(1)

@app.command("hygiene")
def task_hygiene(
    fix: bool = typer.Option(False, "--fix", help="Automatically fix issues where possible"),
    scope: str = typer.Option("all", "--scope", help="Scope: all, terraform, atmos, security"),
    report: bool = typer.Option(False, "--report", help="Generate detailed hygiene report")
):
    """🧹 Comprehensive task hygiene and system maintenance"""
    
    typer.echo("🧹 Running comprehensive task hygiene...")
    
    hygiene_tasks = []
    
    if scope in ["all", "terraform"]:
        hygiene_tasks.extend([
            "lint-terraform",
            "validate-structure"
        ])
    
    if scope in ["all", "atmos"]:
        hygiene_tasks.extend([
            "validate-atmos",
            "check-tools"
        ])
    
    if scope in ["all", "security"]:
        hygiene_tasks.append("security-scan")
    
    # Execute hygiene tasks
    import asyncio
    results = asyncio.run(orchestrator.execute_tasks(hygiene_tasks, parallel=True))
    
    # Generate report if requested
    if report:
        report = orchestrator.get_task_report()
        typer.echo("\n📊 Hygiene Report:")
        typer.echo(f"  Success Rate: {report['summary']['success_rate']*100:.1f}%")
        typer.echo(f"  Total Duration: {report['summary']['total_duration']:.1f}s")
        
        if report['failed_tasks']:
            typer.echo("\n🔧 Issues to address:")
            for failed in report['failed_tasks']:
                typer.echo(f"  • {failed['name']}: {failed['error']}")

@app.command("context")
def manage_context(
    show: bool = typer.Option(False, "--show", help="Show current context"),
    tenant: Optional[str] = typer.Option(None, "--tenant", help="Set default tenant"),
    account: Optional[str] = typer.Option(None, "--account", help="Set default account"),  
    environment: Optional[str] = typer.Option(None, "--environment", help="Set default environment"),
    reset: bool = typer.Option(False, "--reset", help="Reset context to defaults")
):
    """🎯 Manage development context and defaults"""
    
    # Import and delegate to control plane
    from .control_plane import app as control_app
    control_app.commands["context"](show, tenant, account, environment)

@app.command("dashboard")
def unified_dashboard():
    """📊 Unified system dashboard with health metrics"""
    
    # Import and delegate to control plane  
    from .control_plane import app as control_app
    control_app.commands["dashboard"]()

# =============================================================================
# New Enhanced Commands
# =============================================================================

@app.command("status")
def status(
    tenant: Optional[str] = typer.Option(None, "--tenant", "-t", help="Tenant name"),
    account: Optional[str] = typer.Option(None, "--account", "-a", help="Account name"),
    environment: Optional[str] = typer.Option(None, "--environment", "-e", help="Environment name"),
):
    """📊 Show current infrastructure status and recent activity"""
    
    if tenant and account and environment:
        stack = f"orgs/{tenant}/{account}/eu-west-2/{environment}"
        friendly_name = f"{tenant}-{environment}-{account}"
        
        typer.echo(f"📊 Status for environment: {friendly_name}")
        typer.echo("=" * 50)
        
        # Show components
        components = get_stack_components(stack)
        if components:
            typer.echo(f"📦 Components ({len(components)}):")
            for component in components:
                typer.echo(f"   • {component}")
        else:
            typer.echo("📦 No components found")
            
        typer.echo("")
        typer.echo("💡 To see detailed status, run:")
        typer.echo(f"   gaia describe stacks --stack {stack}")
        
    else:
        typer.echo("🌍 Gaia Infrastructure Status")
        typer.echo("=" * 30)
        
        # Show available stacks
        stacks = get_available_stacks()
        typer.echo(f"📋 Available environments ({len(stacks)}):")
        for stack in stacks:
            friendly = re.sub(r'orgs/([^/]+)/([^/]+)/([^/]+)/([^/\s]+)', r'\1-\4-\2', stack)
            typer.echo(f"   • {friendly}")
            
        typer.echo("")
        typer.echo("💡 For detailed status, specify environment:")
        typer.echo("   gaia status --tenant fnx --account dev --environment testenv-01")

@app.command("quick-start")
def quick_start():
    """🚀 Interactive quick start guide for new developers"""
    typer.echo("🌍 Welcome to Gaia CLI!")
    typer.echo("=" * 25)
    typer.echo("")
    
    # Check prerequisites
    typer.echo("🔍 Checking prerequisites...")
    
    if not is_atmos_available():
        typer.echo("❌ Atmos not found")
        show_atmos_installation_help()
        return
    else:
        typer.echo("✅ Atmos is installed")
    
    if not is_in_atmos_project():
        typer.echo("❌ Not in an Atmos project directory")
        typer.echo("💡 Navigate to your Terraform/Atmos project root and try again")
        return
    else:
        typer.echo("✅ In Atmos project directory")
        
    typer.echo("")
    typer.echo("🎯 Common commands to get started:")
    typer.echo("")
    typer.echo("📋 List available environments:")
    typer.echo("   gaia list stacks")
    typer.echo("")
    typer.echo("🔍 Check current status:")
    typer.echo("   gaia status")
    typer.echo("")
    typer.echo("✅ Validate configurations:")
    typer.echo("   gaia workflow validate")
    typer.echo("")
    typer.echo("📋 Plan changes (safe):")
    typer.echo("   gaia workflow plan-environment -t fnx -a dev -e testenv-01")
    typer.echo("")
    typer.echo("🚀 Apply changes:")
    typer.echo("   gaia workflow apply-environment -t fnx -a dev -e testenv-01")
    typer.echo("")
    typer.echo("💡 For more help, run: gaia --help")
    typer.echo("💡 For Makefile shortcuts, run: make help")

@app.command("doctor")
def doctor():
    """🩺 Run diagnostics and show system health"""
    typer.echo("🩺 Gaia System Diagnostics")
    typer.echo("=" * 30)
    typer.echo("")
    
    # Check Atmos
    if is_atmos_available():
        result = subprocess.run(["atmos", "version"], capture_output=True, text=True)
        typer.echo(f"✅ Atmos: {result.stdout.strip()}")
    else:
        typer.echo("❌ Atmos: Not found")
        
    # Check Terraform
    try:
        result = subprocess.run(["terraform", "version"], capture_output=True, text=True)
        version_line = result.stdout.split('\n')[0]
        typer.echo(f"✅ Terraform: {version_line}")
    except:
        typer.echo("❌ Terraform: Not found")
        
    # Check AWS CLI
    try:
        result = subprocess.run(["aws", "--version"], capture_output=True, text=True)
        typer.echo(f"✅ AWS CLI: {result.stderr.strip()}")
    except:
        typer.echo("❌ AWS CLI: Not found")
        
    # Check project structure
    typer.echo("")
    typer.echo("📁 Project Structure:")
    
    if Path("atmos.yaml").exists():
        typer.echo("✅ atmos.yaml found")
    else:
        typer.echo("❌ atmos.yaml missing")
        
    if Path("components/terraform").exists():
        typer.echo("✅ Terraform components directory found")
    else:
        typer.echo("❌ Terraform components directory missing")
        
    if Path("stacks").exists():
        typer.echo("✅ Stacks directory found")
    else:
        typer.echo("❌ Stacks directory missing")
    
    # Check AWS credentials
    typer.echo("")
    typer.echo("🔐 AWS Credentials:")
    try:
        result = subprocess.run(["aws", "sts", "get-caller-identity"], 
                              capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            identity = json.loads(result.stdout)
            typer.echo(f"✅ AWS Account: {identity.get('Account', 'Unknown')}")
            typer.echo(f"✅ AWS User/Role: {identity.get('Arn', 'Unknown')}")
        else:
            typer.echo("❌ AWS credentials not configured or invalid")
    except:
        typer.echo("❌ Unable to check AWS credentials")
    
    typer.echo("")
    typer.echo("💡 For infrastructure-specific diagnostics, run: make doctor")

@app.command("feedback")
def feedback():
    """📝 Provide feedback to improve developer experience"""
    typer.echo("📝 Developer Experience Feedback")
    typer.echo("=" * 35)
    typer.echo("")
    typer.echo("Help us improve your development experience!")
    typer.echo("This will collect anonymous usage data and ask for your feedback.")
    typer.echo("")
    
    if typer.confirm("Would you like to participate?"):
        try:
            subprocess.run(["./scripts/collect-dx-feedback.sh", "interactive"], check=True)
        except subprocess.CalledProcessError:
            typer.echo("❌ Failed to run feedback collection script", err=True)
        except FileNotFoundError:
            typer.echo("❌ Feedback script not found. Are you in the project root?", err=True)
    else:
        typer.echo("Thanks anyway! You can run this anytime with 'gaia feedback'")

@app.command("dx-metrics") 
def dx_metrics():
    """📊 Show developer experience metrics and insights"""
    typer.echo("📊 Developer Experience Metrics")
    typer.echo("=" * 35)
    typer.echo("")
    
    dx_dir = Path(".dx-metrics")
    summary_file = dx_dir / "dx-summary.json"
    
    if not summary_file.exists():
        typer.echo("⚠️  No DX metrics found.")
        typer.echo("")
        typer.echo("💡 To collect metrics:")
        typer.echo("   • Run 'gaia feedback' for full feedback collection")
        typer.echo("   • Run 'make dx-metrics' for automated metrics only")
        return
    
    try:
        import json
        with open(summary_file) as f:
            data = json.load(f)
            
        summary = data.get('summary', {})
        typer.echo(f"📈 Total Feedback Responses: {summary.get('total_feedback_responses', 0)}")
        typer.echo(f"⭐ Average Satisfaction: {summary.get('average_satisfaction', 0):.1f}/10") 
        typer.echo(f"🎯 Average Onboarding Ease: {summary.get('average_onboarding_ease', 0):.1f}/10")
        typer.echo("")
        
        improvement_areas = summary.get('improvement_areas', [])
        if improvement_areas:
            typer.echo("🔧 Focus Areas for Improvement:")
            for area in improvement_areas:
                typer.echo(f"   • {area}")
        
        typer.echo("")
        typer.echo(f"📅 Next Review: {summary.get('next_review', 'Unknown')}")
        
    except Exception as e:
        typer.echo(f"❌ Error reading metrics: {e}", err=True)

@app.command("serve")
def serve(
    port: int = typer.Option(8080, "--port", "-p", help="Port to run the API server on"),
    host: str = typer.Option("localhost", "--host", "-h", help="Host to bind the server to"),
    debug: bool = typer.Option(False, "--debug", help="Enable debug mode"),
):
    """🌐 Start REST API server for terminal-first infrastructure management"""
    
    try:
        # Import Flask and create server
        from flask import Flask, jsonify, request
        import threading
        import signal
        import atexit
        
        typer.echo(f"🚀 Starting Gaia API server...")
        typer.echo(f"🌐 Server will be available at: http://{host}:{port}")
        typer.echo(f"📖 API documentation: http://{host}:{port}/")
        typer.echo("")
        typer.echo("💡 Terminal-first API for power users:")
        typer.echo(f"   curl http://{host}:{port}/stacks")
        typer.echo(f"   curl -X POST http://{host}:{port}/validate")
        typer.echo(f"   curl -X POST http://{host}:{port}/workflows/lint")
        typer.echo("")
        typer.echo("⏹️  Press Ctrl+C to stop the server")
        typer.echo("=" * 50)
        
        # Create Flask app
        flask_app = Flask('gaia-api')
        flask_app.config['DEBUG'] = debug
        
        # Enhanced environment for non-interactive execution
        atmos_env = {
            **os.environ,
            'FORCE_COLOR': '0',
            'NO_COLOR': '1', 
            'TERM': 'dumb',
            'CI': '1',
            'TF_IN_AUTOMATION': '1',
            'ATMOS_TELEMETRY_ENABLED': 'false',
            'DEBIAN_FRONTEND': 'noninteractive'
        }
        
        def execute_atmos_api(command, capture_output=True):
            """Execute atmos command for API responses"""
            full_command = ["atmos"] + command
            try:
                result = subprocess.run(
                    full_command,
                    capture_output=capture_output,
                    text=True,
                    env=atmos_env,
                    timeout=300  # 5 minute timeout
                )
                return {
                    'success': result.returncode == 0,
                    'code': result.returncode,
                    'stdout': result.stdout.strip() if result.stdout else '',
                    'stderr': result.stderr.strip() if result.stderr else '',
                    'command': ' '.join(full_command)
                }
            except subprocess.TimeoutExpired:
                return {
                    'success': False,
                    'code': 124,
                    'stdout': '',
                    'stderr': 'Command timed out after 5 minutes',
                    'command': ' '.join(full_command)
                }
            except Exception as e:
                return {
                    'success': False,
                    'code': 1,
                    'stdout': '',
                    'stderr': str(e),
                    'command': ' '.join(full_command)
                }
        
        # API Documentation endpoint
        @flask_app.route('/')
        def api_docs():
            return jsonify({
                'service': 'Gaia Terminal API',
                'version': '1.0.0',
                'description': 'REST API for terminal-first infrastructure management',
                'powered_by': 'Gaia CLI + Atmos',
                'endpoints': {
                    'GET /': 'API documentation',
                    'GET /health': 'Health check',
                    'GET /stacks': 'List all stacks',
                    'GET /stacks/<stack>/components': 'List components in stack',
                    'POST /stacks/<stack>/validate': 'Validate stack components',
                    'POST /stacks/<stack>/plan': 'Plan stack changes',
                    'GET /components': 'List all components',
                    'POST /components/<component>/validate': 'Validate component',
                    'GET /workflows': 'List available workflows',
                    'POST /workflows/<workflow>': 'Execute workflow',
                    'POST /validate': 'Validate all configurations',
                    'POST /lint': 'Lint all configurations',
                    'GET /status': 'System status',
                },
                'examples': {
                    'List stacks': f'curl http://{host}:{port}/stacks',
                    'Validate stack': f'curl -X POST http://{host}:{port}/stacks/fnx-dev-testenv-01/validate',
                    'Execute lint workflow': f'curl -X POST http://{host}:{port}/workflows/lint',
                    'Plan environment': f'curl -X POST -H "Content-Type: application/json" -d \'{{"tenant":"fnx","account":"dev","environment":"testenv-01"}}\' http://{host}:{port}/workflows/plan-environment'
                }
            })
        
        # Health check
        @flask_app.route('/health')
        def health():
            atmos_available = is_atmos_available()
            in_project = is_in_atmos_project()
            
            return jsonify({
                'status': 'ok' if atmos_available and in_project else 'warning',
                'timestamp': datetime.now().isoformat(),
                'checks': {
                    'atmos_available': atmos_available,
                    'in_atmos_project': in_project,
                    'gaia_version': '1.0.0'
                }
            })
        
        # List stacks
        @flask_app.route('/stacks')
        def list_stacks():
            result = execute_atmos_api(['describe', 'stacks', '--no-color'])
            
            if result['success']:
                stacks = [line.strip() for line in result['stdout'].split('\n') 
                         if line.strip() and not line.startswith('=')]
                return jsonify({
                    'success': True,
                    'stacks': stacks,
                    'count': len(stacks)
                })
            else:
                return jsonify(result), 500
        
        # List components in stack
        @flask_app.route('/stacks/<stack>/components')
        def list_stack_components(stack):
            result = execute_atmos_api(['list', 'components', '-s', stack, '--no-color'])
            
            if result['success']:
                components = [line.strip() for line in result['stdout'].split('\n') if line.strip()]
                return jsonify({
                    'success': True,
                    'stack': stack,
                    'components': components,
                    'count': len(components)
                })
            else:
                return jsonify(result), 500
        
        # Validate stack
        @flask_app.route('/stacks/<stack>/validate', methods=['POST'])
        def validate_stack(stack):
            # Get components first
            comp_result = execute_atmos_api(['list', 'components', '-s', stack, '--no-color'])
            
            if not comp_result['success']:
                return jsonify(comp_result), 500
            
            components = [line.strip() for line in comp_result['stdout'].split('\n') if line.strip()]
            validation_results = []
            
            # Validate each component (limit to first 5 for performance)
            for component in components[:5]:
                result = execute_atmos_api(['terraform', 'validate', component, '-s', stack, '--no-color'])
                validation_results.append({
                    'component': component,
                    'success': result['success'],
                    'stdout': result['stdout'],
                    'stderr': result['stderr']
                })
            
            passed = sum(1 for r in validation_results if r['success'])
            failed = len(validation_results) - passed
            
            return jsonify({
                'success': failed == 0,
                'stack': stack,
                'summary': {
                    'passed': passed,
                    'failed': failed,
                    'total': len(validation_results),
                    'limited_to': min(len(components), 5)
                },
                'results': validation_results
            })
        
        # Plan stack
        @flask_app.route('/stacks/<stack>/plan', methods=['POST'])
        def plan_stack(stack):
            data = request.get_json() or {}
            component = data.get('component')
            
            if component:
                result = execute_atmos_api(['terraform', 'plan', component, '-s', stack, '--no-color'])
                return jsonify(result)
            else:
                return jsonify({
                    'success': False,
                    'error': 'Component parameter required for plan operation',
                    'example': {'component': 'vpc'}
                }), 400
        
        # List all components
        @flask_app.route('/components')
        def list_components():
            try:
                # Find all terraform components
                components_dir = Path('components/terraform')
                if not components_dir.exists():
                    return jsonify({'success': False, 'error': 'Terraform components directory not found'}), 404
                
                components = []
                for component_dir in components_dir.iterdir():
                    if component_dir.is_dir() and (component_dir / 'main.tf').exists():
                        components.append(component_dir.name)
                
                components.sort()
                return jsonify({
                    'success': True,
                    'components': components,
                    'count': len(components)
                })
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)}), 500
        
        # Validate specific component
        @flask_app.route('/components/<component>/validate', methods=['POST'])
        def validate_component(component):
            data = request.get_json() or {}
            stack = data.get('stack', 'fnx-dev-testenv-01')
            
            result = execute_atmos_api(['terraform', 'validate', component, '-s', stack, '--no-color'])
            return jsonify(result)
        
        # List workflows
        @flask_app.route('/workflows')
        def list_workflows():
            try:
                workflows_dir = Path('workflows')
                if not workflows_dir.exists():
                    return jsonify({'success': False, 'error': 'Workflows directory not found'}), 404
                
                workflows = []
                for workflow_file in workflows_dir.glob('*.y*ml'):
                    workflows.append(workflow_file.stem)
                
                workflows.sort()
                return jsonify({
                    'success': True,
                    'workflows': workflows,
                    'count': len(workflows)
                })
            except Exception as e:
                return jsonify({'success': False, 'error': str(e)}), 500
        
        # Execute workflow
        @flask_app.route('/workflows/<workflow>', methods=['POST'])
        def execute_workflow(workflow):
            data = request.get_json() or {}
            
            # Build workflow command
            command = ['workflow', workflow, '--file', f'{workflow}.yaml', '--no-color']
            
            # Add parameters as key=value
            for key, value in data.items():
                command.append(f'{key}={value}')
            
            result = execute_atmos_api(command)
            return jsonify(result)
        
        # Global validate
        @flask_app.route('/validate', methods=['POST'])
        def validate_all():
            result = execute_atmos_api(['workflow', 'validate', '--file', 'validate.yaml', '--no-color'])
            return jsonify(result)
        
        # Global lint
        @flask_app.route('/lint', methods=['POST'])
        def lint_all():
            result = execute_atmos_api(['workflow', 'lint', '--file', 'lint.yaml', '--no-color'])
            return jsonify(result)
        
        # Status endpoint
        @flask_app.route('/status')
        def status():
            stacks = get_available_stacks()
            
            return jsonify({
                'success': True,
                'timestamp': datetime.now().isoformat(),
                'summary': {
                    'total_stacks': len(stacks),
                    'atmos_available': is_atmos_available(),
                    'in_project': is_in_atmos_project()
                },
                'stacks': stacks[:10]  # Limit to first 10 for overview
            })
        
        # Error handlers
        @flask_app.errorhandler(404)
        def not_found(error):
            return jsonify({
                'success': False,
                'error': 'Endpoint not found',
                'available_endpoints': 'See GET / for API documentation'
            }), 404
        
        @flask_app.errorhandler(500)
        def server_error(error):
            return jsonify({
                'success': False,
                'error': 'Internal server error',
                'timestamp': datetime.now().isoformat()
            }), 500
        
        # Graceful shutdown handling
        def signal_handler(sig, frame):
            typer.echo("\n🛑 Shutting down Gaia API server...")
            sys.exit(0)
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
        
        # Start the server
        try:
            flask_app.run(host=host, port=port, debug=debug, use_reloader=False)
        except OSError as e:
            if "Address already in use" in str(e):
                typer.echo(f"❌ Port {port} is already in use. Try a different port with --port", err=True)
                typer.echo(f"💡 Example: gaia serve --port 8081", err=True)
            else:
                typer.echo(f"❌ Failed to start server: {e}", err=True)
            sys.exit(1)
            
    except ImportError:
        typer.echo("❌ Flask not installed. Installing now...", err=True)
        try:
            subprocess.run([sys.executable, "-m", "pip", "install", "flask"], check=True)
            typer.echo("✅ Flask installed. Please run the command again.")
        except subprocess.CalledProcessError:
            typer.echo("❌ Failed to install Flask. Please install it manually:", err=True)
            typer.echo("   pip install flask", err=True)
        sys.exit(1)
    except Exception as e:
        typer.echo(f"❌ Failed to start API server: {e}", err=True)
        sys.exit(1)

if __name__ == "__main__":
    app()