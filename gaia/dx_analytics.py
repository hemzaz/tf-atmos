#!/usr/bin/env python3
"""
Gaia DX Analytics - Developer Experience Metrics and Insights

Tracks and analyzes developer workflows to provide insights for 
continuous DX improvement and personalized recommendations.
"""

import json
import time
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Any
import sqlite3
from dataclasses import dataclass, asdict
from collections import defaultdict, Counter
import typer
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

console = Console()

@dataclass
class DXMetric:
    """Developer Experience Metric"""
    timestamp: str
    user_id: str
    command: str
    duration: float
    success: bool
    context: Dict[str, Any]
    friction_score: int  # 1-10, higher = more friction

@dataclass
class WorkflowPattern:
    """Identified workflow pattern"""
    name: str
    commands: List[str]
    frequency: int
    avg_duration: float
    success_rate: float

class DXAnalytics:
    """Developer Experience Analytics Engine"""
    
    def __init__(self):
        self.project_root = Path.cwd()
        self.db_path = self.project_root / ".gaia" / "dx_analytics.db"
        self.db_path.parent.mkdir(exist_ok=True)
        
        # Initialize database
        self._init_database()
        
        # Load configuration
        self.config = self._load_config()
    
    def _init_database(self):
        """Initialize SQLite database for analytics"""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS metrics (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    command TEXT NOT NULL,
                    duration REAL NOT NULL,
                    success BOOLEAN NOT NULL,
                    context TEXT NOT NULL,
                    friction_score INTEGER NOT NULL
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS workflow_patterns (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL,
                    commands TEXT NOT NULL,
                    frequency INTEGER NOT NULL,
                    avg_duration REAL NOT NULL,
                    success_rate REAL NOT NULL,
                    last_updated TEXT NOT NULL
                )
            """)
            
            conn.execute("""
                CREATE TABLE IF NOT EXISTS dx_feedback (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    timestamp TEXT NOT NULL,
                    user_id TEXT NOT NULL,
                    satisfaction_score INTEGER NOT NULL,
                    friction_points TEXT NOT NULL,
                    suggestions TEXT NOT NULL
                )
            """)
    
    def _load_config(self) -> Dict[str, Any]:
        """Load analytics configuration"""
        config_file = self.project_root / ".gaia" / "dx_config.json"
        if config_file.exists():
            with open(config_file) as f:
                return json.load(f)
        
        # Default configuration
        default_config = {
            "analytics_enabled": True,
            "collect_telemetry": True,
            "user_id": f"dev_{int(time.time())}",
            "friction_thresholds": {
                "command_duration": 30.0,  # Commands over 30s are high friction
                "failure_rate": 0.3,       # >30% failure rate is high friction
                "context_switches": 5      # >5 context switches is high friction
            }
        }
        
        # Save default config
        with open(config_file, 'w') as f:
            json.dump(default_config, f, indent=2)
        
        return default_config
    
    def record_command_execution(
        self,
        command: str,
        duration: float,
        success: bool,
        context: Dict[str, Any] = None
    ):
        """Record a command execution for analytics"""
        
        if not self.config.get("analytics_enabled", True):
            return
        
        # Calculate friction score
        friction_score = self._calculate_friction_score(command, duration, success, context or {})
        
        metric = DXMetric(
            timestamp=datetime.now().isoformat(),
            user_id=self.config["user_id"],
            command=command,
            duration=duration,
            success=success,
            context=context or {},
            friction_score=friction_score
        )
        
        # Store in database
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO metrics 
                (timestamp, user_id, command, duration, success, context, friction_score)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                metric.timestamp,
                metric.user_id, 
                metric.command,
                metric.duration,
                metric.success,
                json.dumps(metric.context),
                metric.friction_score
            ))
    
    def _calculate_friction_score(
        self,
        command: str,
        duration: float,
        success: bool,
        context: Dict[str, Any]
    ) -> int:
        """Calculate friction score (1-10, higher = more friction)"""
        
        score = 1  # Base score for successful quick commands
        
        # Duration-based friction
        if duration > self.config["friction_thresholds"]["command_duration"]:
            score += 3
        elif duration > 10.0:
            score += 1
        
        # Failure adds significant friction
        if not success:
            score += 4
        
        # Context complexity
        if len(context) > 5:
            score += 1
        
        # Command complexity (heuristic)
        if len(command.split()) > 6:
            score += 1
        
        # Special cases
        if "error" in context.get("output", "").lower():
            score += 2
        
        if "retry" in context:
            score += context.get("retry_count", 0)
        
        return min(score, 10)  # Cap at 10
    
    def identify_workflow_patterns(self, days_back: int = 30) -> List[WorkflowPattern]:
        """Identify common workflow patterns"""
        
        cutoff = (datetime.now() - timedelta(days=days_back)).isoformat()
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.execute("""
                SELECT command, duration, success, timestamp
                FROM metrics 
                WHERE timestamp > ?
                ORDER BY timestamp
            """, (cutoff,))
            
            commands = cursor.fetchall()
        
        # Group commands into sessions (within 30 minutes of each other)
        sessions = []
        current_session = []
        
        for command, duration, success, timestamp in commands:
            if current_session:
                last_time = datetime.fromisoformat(current_session[-1][3])
                curr_time = datetime.fromisoformat(timestamp)
                
                if (curr_time - last_time).seconds > 1800:  # 30 minutes
                    if len(current_session) > 1:
                        sessions.append(current_session)
                    current_session = []
            
            current_session.append((command, duration, success, timestamp))
        
        if len(current_session) > 1:
            sessions.append(current_session)
        
        # Identify patterns
        pattern_counter = Counter()
        pattern_stats = defaultdict(lambda: {"durations": [], "successes": []})
        
        for session in sessions:
            if len(session) >= 2:
                command_sequence = tuple(cmd[0] for cmd in session)
                pattern_counter[command_sequence] += 1
                
                total_duration = sum(cmd[1] for cmd in session)
                success_rate = sum(cmd[2] for cmd in session) / len(session)
                
                pattern_stats[command_sequence]["durations"].append(total_duration)
                pattern_stats[command_sequence]["successes"].append(success_rate)
        
        # Convert to WorkflowPattern objects
        patterns = []
        for command_seq, frequency in pattern_counter.most_common(10):
            if frequency >= 2:  # Only patterns that occurred at least twice
                stats = pattern_stats[command_seq]
                avg_duration = sum(stats["durations"]) / len(stats["durations"])
                avg_success_rate = sum(stats["successes"]) / len(stats["successes"])
                
                pattern = WorkflowPattern(
                    name=f"Pattern_{len(patterns)+1}",
                    commands=list(command_seq),
                    frequency=frequency,
                    avg_duration=avg_duration,
                    success_rate=avg_success_rate
                )
                patterns.append(pattern)
        
        return patterns
    
    def get_dx_insights(self, days_back: int = 7) -> Dict[str, Any]:
        """Generate developer experience insights"""
        
        cutoff = (datetime.now() - timedelta(days=days_back)).isoformat()
        
        with sqlite3.connect(self.db_path) as conn:
            # Overall metrics
            cursor = conn.execute("""
                SELECT 
                    COUNT(*) as total_commands,
                    AVG(duration) as avg_duration,
                    AVG(CASE WHEN success THEN 1.0 ELSE 0.0 END) as success_rate,
                    AVG(friction_score) as avg_friction
                FROM metrics 
                WHERE timestamp > ?
            """, (cutoff,))
            
            overall_stats = dict(zip([col[0] for col in cursor.description], cursor.fetchone()))
            
            # Most problematic commands  
            cursor = conn.execute("""
                SELECT command, AVG(friction_score) as friction, COUNT(*) as usage
                FROM metrics 
                WHERE timestamp > ?
                GROUP BY command
                HAVING usage >= 3
                ORDER BY friction DESC
                LIMIT 5
            """, (cutoff,))
            
            friction_commands = [
                {"command": row[0], "friction_score": row[1], "usage_count": row[2]}
                for row in cursor.fetchall()
            ]
            
            # Usage patterns
            cursor = conn.execute("""
                SELECT 
                    strftime('%H', timestamp) as hour,
                    COUNT(*) as commands
                FROM metrics 
                WHERE timestamp > ?
                GROUP BY hour
                ORDER BY commands DESC
            """, (cutoff,))
            
            usage_by_hour = dict(cursor.fetchall())
        
        # Workflow patterns
        patterns = self.identify_workflow_patterns(days_back)
        
        return {
            "period_days": days_back,
            "overall": overall_stats,
            "friction_points": friction_commands,
            "usage_patterns": usage_by_hour,
            "workflow_patterns": [asdict(p) for p in patterns],
            "recommendations": self._generate_recommendations(overall_stats, friction_commands, patterns)
        }
    
    def _generate_recommendations(
        self,
        overall_stats: Dict[str, Any],
        friction_commands: List[Dict],
        patterns: List[WorkflowPattern]
    ) -> List[str]:
        """Generate personalized DX improvement recommendations"""
        
        recommendations = []
        
        # High friction commands
        if friction_commands and friction_commands[0]["friction_score"] > 6:
            cmd = friction_commands[0]["command"]
            recommendations.append(f"Consider creating an alias or shortcut for '{cmd}' (high friction: {friction_commands[0]['friction_score']:.1f}/10)")
        
        # Success rate issues
        if overall_stats.get("success_rate", 1.0) < 0.8:
            recommendations.append("Success rate is below 80% - consider running 'gaia doctor' to check system health")
        
        # Performance issues  
        if overall_stats.get("avg_duration", 0) > 30:
            recommendations.append("Commands are taking longer than expected - check 'gaia dashboard' for system status")
        
        # Workflow optimization
        for pattern in patterns:
            if pattern.avg_duration > 60 and pattern.frequency >= 3:
                recommendations.append(f"Consider creating a custom workflow for {' → '.join(pattern.commands[:3])}... (used {pattern.frequency} times)")
        
        # Context switching
        if len(patterns) > 10:
            recommendations.append("High context switching detected - consider using 'gaia context' to set defaults")
        
        return recommendations

# Global analytics instance
dx_analytics = DXAnalytics()

def track_command(command: str):
    """Decorator to track command execution"""
    def decorator(func):
        def wrapper(*args, **kwargs):
            start_time = time.time()
            success = True
            error = None
            
            try:
                result = func(*args, **kwargs)
                return result
            except Exception as e:
                success = False
                error = str(e)
                raise
            finally:
                duration = time.time() - start_time
                context = {"error": error} if error else {}
                dx_analytics.record_command_execution(command, duration, success, context)
        
        return wrapper
    return decorator

# CLI commands for analytics
analytics_app = typer.Typer(help="Developer Experience Analytics")

@analytics_app.command("insights")
def show_insights(
    days: int = typer.Option(7, "--days", help="Number of days to analyze"),
    export: bool = typer.Option(False, "--export", help="Export insights to JSON file")
):
    """📊 Show developer experience insights and recommendations"""
    
    console.print(Panel("📊 Developer Experience Insights", style="blue"))
    
    insights = dx_analytics.get_dx_insights(days)
    
    # Overall metrics
    overall = insights["overall"]
    table = Table(title=f"📈 Performance (Last {days} days)")
    table.add_column("Metric", style="cyan")
    table.add_column("Value", style="white")
    
    table.add_row("Total Commands", str(overall.get("total_commands", 0)))
    table.add_row("Average Duration", f"{overall.get('avg_duration', 0):.1f}s")
    table.add_row("Success Rate", f"{overall.get('success_rate', 0)*100:.1f}%")
    table.add_row("Average Friction", f"{overall.get('avg_friction', 0):.1f}/10")
    
    console.print(table)
    
    # Friction points
    if insights["friction_points"]:
        console.print("\n🔥 High Friction Commands:")
        for cmd_info in insights["friction_points"][:3]:
            console.print(f"  • {cmd_info['command']} (friction: {cmd_info['friction_score']:.1f}/10, used {cmd_info['usage_count']} times)")
    
    # Workflow patterns
    if insights["workflow_patterns"]:
        console.print("\n🔄 Common Workflow Patterns:")
        for i, pattern in enumerate(insights["workflow_patterns"][:3], 1):
            commands = " → ".join(pattern["commands"][:3])
            if len(pattern["commands"]) > 3:
                commands += "..."
            console.print(f"  {i}. {commands} (used {pattern['frequency']} times, avg {pattern['avg_duration']:.1f}s)")
    
    # Recommendations
    if insights["recommendations"]:
        console.print("\n💡 Personalized Recommendations:")
        for rec in insights["recommendations"]:
            console.print(f"  • {rec}")
    
    # Export option
    if export:
        export_file = Path(f"dx_insights_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
        with open(export_file, 'w') as f:
            json.dump(insights, f, indent=2)
        console.print(f"\n📄 Insights exported to: {export_file}")

@analytics_app.command("patterns")
def show_patterns(
    days: int = typer.Option(30, "--days", help="Number of days to analyze")
):
    """🔄 Show identified workflow patterns"""
    
    patterns = dx_analytics.identify_workflow_patterns(days)
    
    if not patterns:
        console.print("[yellow]No workflow patterns identified yet. Use the system more to build patterns.[/yellow]")
        return
    
    table = Table(title=f"🔄 Workflow Patterns (Last {days} days)")
    table.add_column("Pattern", style="cyan")
    table.add_column("Commands", style="white", max_width=50)
    table.add_column("Frequency", style="green")
    table.add_column("Avg Duration", style="yellow")
    table.add_column("Success Rate", style="blue")
    
    for pattern in patterns:
        commands = " → ".join(pattern.commands[:4])
        if len(pattern.commands) > 4:
            commands += "..."
        
        table.add_row(
            pattern.name,
            commands,
            str(pattern.frequency),
            f"{pattern.avg_duration:.1f}s", 
            f"{pattern.success_rate*100:.1f}%"
        )
    
    console.print(table)

if __name__ == "__main__":
    analytics_app()