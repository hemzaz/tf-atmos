#!/usr/bin/env python3
"""
Gaia Control Plane - Unified DX Interface with ChromaDB Intelligence

Centralizes all task hygiene and system management through an intelligent
command interface that learns from usage patterns and provides contextual help.
"""

import asyncio
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any
import typer
from rich.console import Console
from rich.panel import Panel
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn

try:
    import chromadb
    from chromadb.config import Settings
    CHROMADB_AVAILABLE = True
except ImportError:
    CHROMADB_AVAILABLE = False

console = Console()
app = typer.Typer(
    help="🧠 Gaia Control Plane - Intelligent Infrastructure Management",
    rich_markup_mode="rich"
)

class GaiaControlPlane:
    def __init__(self):
        self.project_root = Path.cwd()
        self.knowledge_base = None
        self.usage_patterns = []
        self.context_history = []
        
        # Initialize knowledge base if ChromaDB is available
        if CHROMADB_AVAILABLE:
            self._init_knowledge_base()
        
        # Load existing patterns
        self._load_usage_patterns()
    
    def _init_knowledge_base(self):
        """Initialize ChromaDB knowledge base for intelligent assistance"""
        try:
            client = chromadb.PersistentClient(
                path=str(self.project_root / ".gaia" / "knowledge"),
                settings=Settings(anonymized_telemetry=False)
            )
            
            # Create collections for different knowledge domains
            self.knowledge_base = {
                'commands': client.get_or_create_collection(
                    name="commands",
                    metadata={"description": "Available commands and their usage patterns"}
                ),
                'workflows': client.get_or_create_collection(
                    name="workflows", 
                    metadata={"description": "Infrastructure workflows and best practices"}
                ),
                'troubleshooting': client.get_or_create_collection(
                    name="troubleshooting",
                    metadata={"description": "Common issues and their solutions"}
                ),
                'patterns': client.get_or_create_collection(
                    name="patterns",
                    metadata={"description": "User behavior patterns and preferences"}
                )
            }
            
            # Seed initial knowledge
            self._seed_knowledge_base()
            
        except Exception as e:
            console.print(f"[yellow]Warning: ChromaDB initialization failed: {e}[/yellow]")
            self.knowledge_base = None
    
    def _seed_knowledge_base(self):
        """Seed the knowledge base with essential information"""
        if not self.knowledge_base:
            return
            
        # Common workflows and their contexts
        workflows_data = [
            {
                "id": "new-env-setup",
                "command": "gaia smart onboard-environment",
                "description": "Complete new environment setup with validation",
                "context": "new environment, onboarding, infrastructure setup",
                "difficulty": "beginner"
            },
            {
                "id": "quick-validation",
                "command": "gaia smart validate --quick",
                "description": "Quick validation of current stack",
                "context": "validation, testing, pre-deployment",
                "difficulty": "beginner"
            },
            {
                "id": "production-deploy",
                "command": "gaia smart deploy --environment=production --safety-checks",
                "description": "Safe production deployment with all checks",
                "context": "production, deployment, safety",
                "difficulty": "advanced"
            }
        ]
        
        for workflow in workflows_data:
            self.knowledge_base['workflows'].add(
                documents=[workflow['description']],
                metadatas=[{
                    'command': workflow['command'],
                    'context': workflow['context'],
                    'difficulty': workflow['difficulty']
                }],
                ids=[workflow['id']]
            )
    
    def _load_usage_patterns(self):
        """Load historical usage patterns for personalized recommendations"""
        patterns_file = self.project_root / ".gaia" / "usage_patterns.json"
        if patterns_file.exists():
            try:
                with open(patterns_file) as f:
                    self.usage_patterns = json.load(f)
            except Exception:
                self.usage_patterns = []
    
    def _record_usage(self, command: str, context: Dict[str, Any], success: bool):
        """Record command usage for learning user patterns"""
        pattern = {
            'timestamp': datetime.now().isoformat(),
            'command': command,
            'context': context,
            'success': success,
            'session_id': getattr(self, 'session_id', 'unknown')
        }
        
        self.usage_patterns.append(pattern)
        
        # Persist patterns (keep only last 1000 entries)
        patterns_file = self.project_root / ".gaia" / "usage_patterns.json"
        patterns_file.parent.mkdir(exist_ok=True)
        
        with open(patterns_file, 'w') as f:
            json.dump(self.usage_patterns[-1000:], f, indent=2)
    
    def get_intelligent_suggestions(self, query: str, limit: int = 3) -> List[Dict]:
        """Get intelligent command suggestions based on query and patterns"""
        if not self.knowledge_base:
            return self._fallback_suggestions(query)
        
        try:
            # Search across all collections
            suggestions = []
            
            for collection_name, collection in self.knowledge_base.items():
                results = collection.query(
                    query_texts=[query],
                    n_results=min(limit, 5)
                )
                
                for i, doc in enumerate(results['documents'][0]):
                    metadata = results['metadatas'][0][i]
                    suggestions.append({
                        'source': collection_name,
                        'command': metadata.get('command', 'N/A'),
                        'description': doc,
                        'relevance': results['distances'][0][i] if results['distances'] else 1.0,
                        'metadata': metadata
                    })
            
            # Sort by relevance and return top suggestions
            suggestions.sort(key=lambda x: x['relevance'])
            return suggestions[:limit]
            
        except Exception as e:
            console.print(f"[yellow]Search error: {e}[/yellow]")
            return self._fallback_suggestions(query)
    
    def _fallback_suggestions(self, query: str) -> List[Dict]:
        """Provide fallback suggestions when ChromaDB is not available"""
        common_suggestions = {
            'validate': [
                {'command': 'gaia workflow validate', 'description': 'Validate all configurations'},
                {'command': 'gaia terraform validate <component> -s <stack>', 'description': 'Validate specific component'}
            ],
            'deploy': [
                {'command': 'gaia workflow plan-environment -t fnx -a dev -e testenv-01', 'description': 'Plan deployment'},
                {'command': 'gaia workflow apply-environment -t fnx -a dev -e testenv-01', 'description': 'Apply deployment'}
            ],
            'setup': [
                {'command': 'gaia quick-start', 'description': 'Interactive setup guide'},
                {'command': 'gaia doctor', 'description': 'System health check'}
            ]
        }
        
        query_lower = query.lower()
        for keyword, suggestions in common_suggestions.items():
            if keyword in query_lower:
                return [{'command': s['command'], 'description': s['description'], 'source': 'fallback'} 
                       for s in suggestions]
        
        return [
            {'command': 'gaia quick-start', 'description': 'Get started with interactive guide', 'source': 'fallback'},
            {'command': 'gaia status', 'description': 'Show current system status', 'source': 'fallback'},
            {'command': 'gaia help', 'description': 'Show all available commands', 'source': 'fallback'}
        ]

# Global control plane instance
control_plane = GaiaControlPlane()

@app.command("smart")
def smart_command(
    query: str = typer.Argument(help="Natural language query or task description"),
    execute: bool = typer.Option(False, "--execute", "-x", help="Execute the best suggestion automatically"),
    suggestions: int = typer.Option(3, "--suggestions", "-n", help="Number of suggestions to show")
):
    """🧠 Intelligent command suggestions based on natural language query"""
    
    console.print(Panel(f"🤔 Understanding: [bold cyan]{query}[/bold cyan]"))
    
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Analyzing query and finding best matches...", total=None)
        
        suggestions_list = control_plane.get_intelligent_suggestions(query, suggestions)
        progress.update(task, description="Found suggestions!")
    
    if not suggestions_list:
        console.print("[red]No suggestions found. Try 'gaia help' for available commands.[/red]")
        return
    
    # Display suggestions
    table = Table(title="💡 Smart Suggestions", show_header=True)
    table.add_column("Command", style="cyan", no_wrap=True)
    table.add_column("Description", style="white")
    table.add_column("Source", style="dim")
    
    for i, suggestion in enumerate(suggestions_list):
        table.add_row(
            f"{i+1}. {suggestion['command']}", 
            suggestion['description'], 
            suggestion.get('source', 'unknown')
        )
    
    console.print(table)
    
    if execute and suggestions_list:
        # Execute the best suggestion
        best_command = suggestions_list[0]['command']
        console.print(f"\n[green]Executing:[/green] {best_command}")
        
        try:
            # Parse and execute the command
            cmd_parts = best_command.split()
            if cmd_parts[0] == 'gaia':
                # Execute Gaia command
                subprocess.run(cmd_parts, check=True)
                control_plane._record_usage(best_command, {'query': query}, True)
            else:
                console.print("[yellow]Command requires manual execution[/yellow]")
        except subprocess.CalledProcessError as e:
            console.print(f"[red]Execution failed: {e}[/red]")
            control_plane._record_usage(best_command, {'query': query}, False)
    else:
        console.print("\n💡 To execute a suggestion: [cyan]gaia smart \"your query\" --execute[/cyan]")

@app.command("learn")
def learn_command(
    feedback: str = typer.Option(None, "--feedback", "-f", help="Provide feedback on last command"),
    pattern: str = typer.Option(None, "--pattern", "-p", help="Teach a new pattern")
):
    """📚 Teach Gaia about your preferences and patterns"""
    
    if feedback:
        console.print(f"[green]Thanks for the feedback:[/green] {feedback}")
        # Record feedback for learning
        
    if pattern:
        console.print(f"[blue]Learning new pattern:[/blue] {pattern}")
        # Add to knowledge base
    
    if not feedback and not pattern:
        # Interactive learning session
        console.print(Panel("📚 Interactive Learning Session", style="blue"))
        console.print("This feature helps Gaia learn your workflow preferences...")
        console.print("Coming soon: Interactive pattern learning!")

@app.command("context")  
def context_command(
    show: bool = typer.Option(False, "--show", help="Show current context"),
    set_tenant: Optional[str] = typer.Option(None, "--tenant", help="Set default tenant"),
    set_account: Optional[str] = typer.Option(None, "--account", help="Set default account"),
    set_environment: Optional[str] = typer.Option(None, "--environment", help="Set default environment")
):
    """🎯 Manage context and defaults for streamlined operations"""
    
    context_file = control_plane.project_root / ".gaia" / "context.json"
    context_file.parent.mkdir(exist_ok=True)
    
    # Load existing context
    context = {}
    if context_file.exists():
        with open(context_file) as f:
            context = json.load(f)
    
    # Update context
    if set_tenant:
        context['tenant'] = set_tenant
    if set_account:
        context['account'] = set_account  
    if set_environment:
        context['environment'] = set_environment
    
    # Save context
    if any([set_tenant, set_account, set_environment]):
        with open(context_file, 'w') as f:
            json.dump(context, f, indent=2)
        console.print("[green]Context updated![/green]")
    
    # Display current context
    if show or not any([set_tenant, set_account, set_environment]):
        table = Table(title="🎯 Current Context")
        table.add_column("Setting", style="cyan")
        table.add_column("Value", style="white")
        
        table.add_row("Tenant", context.get('tenant', '[dim]Not set[/dim]'))
        table.add_row("Account", context.get('account', '[dim]Not set[/dim]'))
        table.add_row("Environment", context.get('environment', '[dim]Not set[/dim]'))
        
        console.print(table)
        
        if context.get('tenant') and context.get('account') and context.get('environment'):
            stack = f"{context['tenant']}-{context['environment']}-{context['account']}"
            console.print(f"\n💡 Current stack: [bold cyan]{stack}[/bold cyan]")

@app.command("dashboard")
def dashboard():
    """📊 Show unified system dashboard"""
    
    console.print(Panel("🌍 Gaia Control Plane Dashboard", style="bold blue"))
    
    # System Health
    console.print("\n[bold]🔋 System Health[/bold]")
    health_table = Table()
    health_table.add_column("Component", style="white")
    health_table.add_column("Status", style="green")
    health_table.add_column("Info", style="dim")
    
    # Check various system components
    components = [
        ("Atmos", check_atmos()),
        ("Terraform", check_terraform()),
        ("AWS CLI", check_aws_cli()),
        ("Project Structure", check_project_structure())
    ]
    
    for name, (status, info) in components:
        color = "green" if status else "red"
        status_text = "✅ OK" if status else "❌ Issue"
        health_table.add_row(name, f"[{color}]{status_text}[/{color}]", info)
    
    console.print(health_table)
    
    # Recent Activity
    console.print("\n[bold]📈 Recent Activity[/bold]")
    if control_plane.usage_patterns:
        recent = control_plane.usage_patterns[-5:]
        activity_table = Table()
        activity_table.add_column("Time", style="dim")
        activity_table.add_column("Command", style="cyan")
        activity_table.add_column("Status", style="white")
        
        for pattern in recent:
            time_str = datetime.fromisoformat(pattern['timestamp']).strftime('%H:%M:%S')
            status = "✅" if pattern['success'] else "❌"
            activity_table.add_row(time_str, pattern['command'], status)
        
        console.print(activity_table)
    else:
        console.print("[dim]No recent activity recorded[/dim]")

def check_atmos() -> Tuple[bool, str]:
    """Check Atmos availability"""
    try:
        result = subprocess.run(['atmos', 'version'], capture_output=True, text=True, timeout=5)
        return True, result.stdout.strip().split('\n')[0] if result.stdout else "Available"
    except:
        return False, "Not found or not working"

def check_terraform() -> Tuple[bool, str]:
    """Check Terraform availability"""
    try:
        result = subprocess.run(['terraform', 'version'], capture_output=True, text=True, timeout=5)
        return True, result.stdout.strip().split('\n')[0] if result.stdout else "Available"
    except:
        return False, "Not found or not working"

def check_aws_cli() -> Tuple[bool, str]:
    """Check AWS CLI availability"""  
    try:
        result = subprocess.run(['aws', '--version'], capture_output=True, text=True, timeout=5)
        version = result.stderr.strip() if result.stderr else result.stdout.strip()
        return True, version.split()[0] if version else "Available"
    except:
        return False, "Not found or not working"

def check_project_structure() -> Tuple[bool, str]:
    """Check project structure"""
    required_paths = ['atmos.yaml', 'components/terraform', 'stacks']
    missing = [p for p in required_paths if not Path(p).exists()]
    
    if missing:
        return False, f"Missing: {', '.join(missing)}"
    return True, "All required files present"

if __name__ == "__main__":
    app()