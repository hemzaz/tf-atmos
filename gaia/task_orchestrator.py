#!/usr/bin/env python3
"""
Gaia Task Orchestrator - Centralized Task Hygiene and System Management

Consolidates scattered tools (scripts, workflows, makefiles) into cohesive,
intelligent task orchestration with automatic dependency resolution and
parallel execution capabilities.
"""

import asyncio
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Any, Callable
import typer
from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, BarColumn, TextColumn, TimeElapsedColumn
from rich.tree import Tree
from rich.live import Live
from enum import Enum

console = Console()

class TaskStatus(Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    SKIPPED = "skipped"

class TaskPriority(Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
    CRITICAL = 4

@dataclass
class Task:
    """Represents a single task in the orchestration system"""
    id: str
    name: str
    description: str
    command: List[str]
    dependencies: List[str] = field(default_factory=list)
    status: TaskStatus = TaskStatus.PENDING
    priority: TaskPriority = TaskPriority.MEDIUM
    timeout: int = 300  # 5 minutes default
    retry_count: int = 0
    max_retries: int = 2
    context: Dict[str, Any] = field(default_factory=dict)
    start_time: Optional[datetime] = None
    end_time: Optional[datetime] = None
    output: str = ""
    error: str = ""
    
    def duration(self) -> Optional[float]:
        """Calculate task duration in seconds"""
        if self.start_time and self.end_time:
            return (self.end_time - self.start_time).total_seconds()
        return None

class TaskOrchestrator:
    """Centralized task orchestration engine"""
    
    def __init__(self):
        self.tasks: Dict[str, Task] = {}
        self.task_graph: Dict[str, Set[str]] = {}
        self.execution_history: List[Dict] = []
        self.project_root = Path.cwd()
        
        # Load task definitions
        self._load_task_definitions()
        
    def _load_task_definitions(self):
        """Load predefined task definitions"""
        
        # Infrastructure validation tasks
        self.define_task(
            "validate-structure", 
            "Validate project structure",
            ["python3", "-c", """
import sys
from pathlib import Path
required = ['atmos.yaml', 'components/terraform', 'stacks']
missing = [p for p in required if not Path(p).exists()]
if missing:
    print(f'Missing: {", ".join(missing)}', file=sys.stderr)
    sys.exit(1)
print('✅ Project structure valid')
"""],
            priority=TaskPriority.CRITICAL
        )
        
        self.define_task(
            "check-tools",
            "Check required tools availability", 
            ["bash", "-c", """
set -e
echo "Checking Atmos..." && atmos version > /dev/null
echo "Checking Terraform..." && terraform version > /dev/null  
echo "Checking AWS CLI..." && aws --version > /dev/null
echo "✅ All tools available"
"""],
            dependencies=["validate-structure"],
            priority=TaskPriority.HIGH
        )
        
        self.define_task(
            "lint-terraform",
            "Lint Terraform configurations",
            ["terraform", "fmt", "-check", "-recursive", "./components/terraform"],
            dependencies=["check-tools"],
            priority=TaskPriority.MEDIUM
        )
        
        self.define_task(
            "validate-atmos",
            "Validate Atmos configuration", 
            ["atmos", "validate", "stacks"],
            dependencies=["check-tools"],
            priority=TaskPriority.HIGH
        )
        
        # Security and compliance tasks
        self.define_task(
            "security-scan",
            "Run security scan on Terraform",
            ["bash", "-c", """
if command -v tfsec >/dev/null 2>&1; then
    tfsec ./components/terraform/ --format compact
elif command -v checkov >/dev/null 2>&1; then  
    checkov -d ./components/terraform/ --compact
else
    echo "⚠️ No security scanner found (tfsec/checkov)"
    exit 0
fi
"""],
            dependencies=["lint-terraform"],
            priority=TaskPriority.MEDIUM
        )
        
        # Environment-specific tasks (will be dynamically generated)
        
    def define_task(
        self,
        task_id: str,
        name: str, 
        command: List[str],
        dependencies: List[str] = None,
        priority: TaskPriority = TaskPriority.MEDIUM,
        timeout: int = 300,
        context: Dict[str, Any] = None
    ) -> Task:
        """Define a new task in the orchestration system"""
        
        task = Task(
            id=task_id,
            name=name,
            description=name,
            command=command,
            dependencies=dependencies or [],
            priority=priority,
            timeout=timeout,
            context=context or {}
        )
        
        self.tasks[task_id] = task
        self.task_graph[task_id] = set(dependencies or [])
        
        return task
    
    def define_environment_tasks(self, tenant: str, account: str, environment: str):
        """Define environment-specific tasks dynamically"""
        stack = f"{tenant}-{environment}-{account}"
        stack_path = f"orgs/{tenant}/{account}/eu-west-2/{environment}"
        
        # Environment validation
        self.define_task(
            f"validate-{stack}",
            f"Validate {stack} components",
            ["atmos", "workflow", "validate", f"tenant={tenant}", f"account={account}", f"environment={environment}"],
            dependencies=["validate-atmos"],
            context={"stack": stack, "tenant": tenant, "account": account, "environment": environment}
        )
        
        # Environment planning  
        self.define_task(
            f"plan-{stack}",
            f"Plan {stack} infrastructure",
            ["atmos", "workflow", "plan-environment", f"tenant={tenant}", f"account={account}", f"environment={environment}"],
            dependencies=[f"validate-{stack}"],
            context={"stack": stack, "tenant": tenant, "account": account, "environment": environment}
        )
        
        # Component-specific tasks for the environment
        components = self._get_stack_components(stack_path)
        for component in components:
            self.define_task(
                f"validate-{stack}-{component}",
                f"Validate {component} in {stack}",
                ["atmos", "terraform", "validate", component, "-s", stack_path],
                dependencies=[f"validate-{stack}"],
                context={"component": component, "stack": stack}
            )
    
    def _get_stack_components(self, stack_path: str) -> List[str]:
        """Get components for a specific stack"""
        try:
            result = subprocess.run(
                ["atmos", "list", "components", "-s", stack_path],
                capture_output=True, text=True, timeout=30
            )
            if result.returncode == 0:
                return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        except Exception:
            pass
        return []
    
    def get_execution_plan(self, target_tasks: List[str]) -> List[List[str]]:
        """Generate execution plan with proper dependency ordering"""
        
        # Validate all target tasks exist
        missing_tasks = [t for t in target_tasks if t not in self.tasks]
        if missing_tasks:
            raise ValueError(f"Unknown tasks: {missing_tasks}")
        
        # Find all tasks needed (including dependencies)
        needed_tasks = set()
        
        def collect_dependencies(task_id: str):
            needed_tasks.add(task_id)
            for dep in self.task_graph[task_id]:
                if dep not in needed_tasks:
                    collect_dependencies(dep)
        
        for target in target_tasks:
            collect_dependencies(target)
        
        # Topological sort for execution order
        execution_layers = []
        remaining_tasks = needed_tasks.copy()
        
        while remaining_tasks:
            # Find tasks with no remaining dependencies
            ready_tasks = []
            for task_id in remaining_tasks:
                deps_satisfied = all(dep not in remaining_tasks for dep in self.task_graph[task_id])
                if deps_satisfied:
                    ready_tasks.append(task_id)
            
            if not ready_tasks:
                # Circular dependency detected
                raise ValueError(f"Circular dependency detected in remaining tasks: {remaining_tasks}")
            
            # Sort by priority within the layer
            ready_tasks.sort(key=lambda t: self.tasks[t].priority.value, reverse=True)
            execution_layers.append(ready_tasks)
            
            # Remove completed tasks
            for task_id in ready_tasks:
                remaining_tasks.remove(task_id)
        
        return execution_layers
    
    async def execute_tasks(self, target_tasks: List[str], parallel: bool = True) -> Dict[str, bool]:
        """Execute tasks with proper dependency resolution"""
        
        execution_plan = self.get_execution_plan(target_tasks)
        results = {}
        
        console.print(Panel("🚀 Task Execution Plan", style="blue"))
        
        # Display execution plan
        tree = Tree("📋 Execution Order")
        for layer_num, layer in enumerate(execution_plan, 1):
            layer_node = tree.add(f"Layer {layer_num}")
            for task_id in layer:
                task = self.tasks[task_id]
                layer_node.add(f"{task.name} [dim]({task.priority.name.lower()})[/dim]")
        
        console.print(tree)
        
        # Execute layers sequentially, tasks within layers in parallel
        with Progress(
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TextColumn("[progress.percentage]{task.percentage:>3.0f}%"),
            TimeElapsedColumn(),
            console=console
        ) as progress:
            
            total_progress = progress.add_task("Overall Progress", total=len(self.tasks))
            
            for layer_num, layer in enumerate(execution_plan, 1):
                layer_task = progress.add_task(f"Layer {layer_num}", total=len(layer))
                
                if parallel and len(layer) > 1:
                    # Execute layer tasks in parallel
                    layer_results = await self._execute_layer_parallel(layer, progress, layer_task)
                else:
                    # Execute layer tasks sequentially
                    layer_results = await self._execute_layer_sequential(layer, progress, layer_task)
                
                results.update(layer_results)
                
                # Check if any critical task failed
                failed_critical = any(
                    not success and self.tasks[task_id].priority == TaskPriority.CRITICAL 
                    for task_id, success in layer_results.items()
                )
                
                if failed_critical:
                    console.print("[red]❌ Critical task failed, stopping execution[/red]")
                    break
                
                progress.update(total_progress, advance=len(layer))
        
        return results
    
    async def _execute_layer_parallel(self, layer: List[str], progress: Progress, layer_task) -> Dict[str, bool]:
        """Execute a layer of tasks in parallel"""
        
        async def execute_single_task(task_id: str) -> tuple[str, bool]:
            success = await self._execute_task(task_id, progress)
            progress.update(layer_task, advance=1)
            return task_id, success
        
        # Execute all tasks in the layer concurrently
        tasks_coroutines = [execute_single_task(task_id) for task_id in layer]
        layer_results = await asyncio.gather(*tasks_coroutines)
        
        return dict(layer_results)
    
    async def _execute_layer_sequential(self, layer: List[str], progress: Progress, layer_task) -> Dict[str, bool]:
        """Execute a layer of tasks sequentially"""
        results = {}
        
        for task_id in layer:
            success = await self._execute_task(task_id, progress)
            results[task_id] = success
            progress.update(layer_task, advance=1)
            
            # Stop on first failure for sequential execution
            if not success and self.tasks[task_id].priority == TaskPriority.CRITICAL:
                break
        
        return results
    
    async def _execute_task(self, task_id: str, progress: Progress) -> bool:
        """Execute a single task"""
        task = self.tasks[task_id]
        task.status = TaskStatus.RUNNING
        task.start_time = datetime.now()
        
        task_progress = progress.add_task(f"  {task.name}", total=1)
        
        try:
            # Execute the command
            loop = asyncio.get_event_loop()
            
            # Run in thread pool to avoid blocking
            with ThreadPoolExecutor() as executor:
                future = loop.run_in_executor(
                    executor,
                    lambda: subprocess.run(
                        task.command,
                        capture_output=True,
                        text=True,
                        timeout=task.timeout,
                        cwd=self.project_root
                    )
                )
                
                result = await future
            
            task.output = result.stdout
            task.error = result.stderr
            task.end_time = datetime.now()
            
            if result.returncode == 0:
                task.status = TaskStatus.COMPLETED
                progress.update(task_progress, completed=1, description=f"  ✅ {task.name}")
                return True
            else:
                task.status = TaskStatus.FAILED
                progress.update(task_progress, completed=1, description=f"  ❌ {task.name}")
                
                # Retry logic
                if task.retry_count < task.max_retries:
                    task.retry_count += 1
                    console.print(f"[yellow]Retrying {task.name} ({task.retry_count}/{task.max_retries})[/yellow]")
                    return await self._execute_task(task_id, progress)
                
                return False
                
        except asyncio.TimeoutError:
            task.status = TaskStatus.FAILED
            task.end_time = datetime.now()
            task.error = f"Task timed out after {task.timeout} seconds"
            progress.update(task_progress, completed=1, description=f"  ⏰ {task.name}")
            return False
            
        except Exception as e:
            task.status = TaskStatus.FAILED
            task.end_time = datetime.now()
            task.error = str(e)
            progress.update(task_progress, completed=1, description=f"  💥 {task.name}")
            return False
    
    def get_task_report(self) -> Dict[str, Any]:
        """Generate execution report"""
        completed_tasks = [t for t in self.tasks.values() if t.status == TaskStatus.COMPLETED]
        failed_tasks = [t for t in self.tasks.values() if t.status == TaskStatus.FAILED]
        
        total_duration = sum(t.duration() or 0 for t in completed_tasks)
        
        return {
            'summary': {
                'total_tasks': len(self.tasks),
                'completed': len(completed_tasks),
                'failed': len(failed_tasks),
                'success_rate': len(completed_tasks) / len(self.tasks) if self.tasks else 0,
                'total_duration': total_duration
            },
            'failed_tasks': [
                {
                    'id': t.id,
                    'name': t.name,
                    'error': t.error,
                    'retry_count': t.retry_count
                } for t in failed_tasks
            ],
            'performance': {
                'fastest_task': min((t for t in completed_tasks if t.duration()), 
                                   key=lambda x: x.duration(), default=None),
                'slowest_task': max((t for t in completed_tasks if t.duration()),
                                   key=lambda x: x.duration(), default=None)
            }
        }
    
    def reset_tasks(self):
        """Reset all task states for fresh execution"""
        for task in self.tasks.values():
            task.status = TaskStatus.PENDING
            task.retry_count = 0
            task.start_time = None
            task.end_time = None
            task.output = ""
            task.error = ""

# Create global orchestrator instance
orchestrator = TaskOrchestrator()