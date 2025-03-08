"""
Component discovery and dependency resolution.
Provides functionality to discover Terraform components and their dependencies.
"""

import os
import re
import subprocess
import threading
from typing import Dict, List, Set, Tuple, Optional, Any
from pathlib import Path
import networkx as nx
import yaml

from gaia.logger import get_logger
from gaia.config import get_config

# Global lock for component discovery and dependency resolution
discovery_lock = threading.RLock()
from gaia.utils import validate_path, run_command

logger = get_logger(__name__)
config = get_config()


class ComponentDiscovery:
    """Discover and process Terraform components."""
    
    # Class-level cache for component lists and configs by stack name
    _component_cache: Dict[str, List[str]] = {}
    _config_cache: Dict[str, Dict[str, Dict[str, Any]]] = {}
    _dependency_graph_cache: Dict[str, nx.DiGraph] = {}
    _cache_lock = threading.RLock()
    
    def __init__(self, stack: str, reverse: bool = False):
        """Initialize component discovery for a specific stack."""
        self.stack = stack
        self.reverse = reverse
        self.components_dir = Path(config.paths.components_dir)
        
        # Create a cache key that includes reverse parameter
        self.cache_key = f"{stack}:{reverse}"
        
        # Parse stack parts
        stack_parts = stack.split('-')
        if len(stack_parts) < 3:
            raise ValueError(f"Invalid stack name: {stack}. Expected format: tenant-account-environment")
        
        self.tenant = stack_parts[0]
        self.account = stack_parts[1]
        self.environment = '-'.join(stack_parts[2:])  # Environment might contain hyphens
        
        # Initialize empty dependency graph
        self.dependency_graph = nx.DiGraph()
        
        # For instance-level caching discovered components and their configs
        self._components: List[str] = []
        self._component_configs: Dict[str, Dict[str, Any]] = {}
    
    def get_components(self) -> List[str]:
        """Get all components for the current stack."""
        # First check instance cache
        if self._components:
            return self._components
        
        # Then check class-level cache
        with self._cache_lock:
            if self.stack in self._component_cache:
                self._components = self._component_cache[self.stack]
                logger.debug(f"Using cached component list for stack: {self.stack}")
                return self._components
        
        logger.info(f"Discovering components for stack: {self.stack}")
        
        try:
            # Use atmos command to get stack components
            cmd = ["atmos", "components", "list", "-s", self.stack]
            result = run_command(cmd)
            
            # Parse output to get component list
            self._components = [line.strip() for line in result.stdout.split('\n') if line.strip()]
            logger.info(f"Found {len(self._components)} components")
            
            # Update class-level cache
            with self._cache_lock:
                self._component_cache[self.stack] = self._components
                
            return self._components
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to discover components: {e}")
            # Safely access the output attribute if it exists
            if hasattr(e, 'output') and e.output:
                logger.debug(f"Command output: {e.output}")
            elif hasattr(e, 'stderr') and e.stderr:
                logger.debug(f"Command stderr: {e.stderr}")
            return []
    
    def get_component_config(self, component: str) -> Dict[str, Any]:
        """Get component configuration for a specific component."""
        # First check instance cache
        if component in self._component_configs:
            return self._component_configs[component]
        
        # Then check class-level cache
        cache_key = f"{self.stack}:{component}"
        with self._cache_lock:
            if self.stack in self._config_cache and component in self._config_cache[self.stack]:
                self._component_configs[component] = self._config_cache[self.stack][component]
                logger.debug(f"Using cached config for component {component} in stack {self.stack}")
                return self._component_configs[component]
        
        try:
            # Use atmos command to get component config
            cmd = ["atmos", "describe", "component", component, "-s", self.stack, "-f", "yaml"]
            result = run_command(cmd)
            
            # Parse YAML output
            config_data = yaml.safe_load(result.stdout)
            self._component_configs[component] = config_data
            
            # Update class-level cache
            with self._cache_lock:
                if self.stack not in self._config_cache:
                    self._config_cache[self.stack] = {}
                self._config_cache[self.stack][component] = config_data
                
            return config_data
            
        except subprocess.CalledProcessError as e:
            logger.error(f"Failed to get config for component {component}: {e}")
            # Safely access the output attribute if it exists
            if hasattr(e, 'output') and e.output:
                logger.debug(f"Command output: {e.output}")
            elif hasattr(e, 'stderr') and e.stderr:
                logger.debug(f"Command stderr: {e.stderr}")
            return {}
        except yaml.YAMLError as e:
            logger.error(f"Failed to parse YAML for component {component}: {e}")
            return {}
    
    def get_component_dependencies(self, component: str) -> List[str]:
        """Get dependencies for a specific component."""
        config_data = self.get_component_config(component)
        
        # Extract dependencies from config
        dependencies = []
        
        # Check various locations where dependencies might be defined
        if "dependencies" in config_data:
            if isinstance(config_data["dependencies"], list):
                dependencies.extend(config_data["dependencies"])
            elif isinstance(config_data["dependencies"], dict):
                for dep_key, dep_value in config_data["dependencies"].items():
                    if isinstance(dep_value, list):
                        dependencies.extend(dep_value)
        
        # Extract terraform_state dependencies
        if "terraform_state" in config_data:
            terraform_state = config_data["terraform_state"]
            if isinstance(terraform_state, dict) and "dependencies" in terraform_state:
                state_deps = terraform_state["dependencies"]
                if isinstance(state_deps, list):
                    dependencies.extend(state_deps)
        
        # Filter out non-component dependencies
        valid_components = set(self.get_components())
        return [dep for dep in dependencies if dep in valid_components]
    
    def build_dependency_graph(self) -> nx.DiGraph:
        """Build a directed graph of component dependencies."""
        # First check instance-level cache
        if self.dependency_graph.nodes():
            return self.dependency_graph
        
        # Then check class-level cache
        with self._cache_lock:
            if self.cache_key in self._dependency_graph_cache:
                self.dependency_graph = self._dependency_graph_cache[self.cache_key].copy()
                logger.debug(f"Using cached dependency graph for {self.cache_key}")
                return self.dependency_graph
                
        components = self.get_components()
        
        # Add all components as nodes
        for component in components:
            self.dependency_graph.add_node(component)
        
        # Add dependencies as edges
        for component in components:
            deps = self.get_component_dependencies(component)
            for dep in deps:
                if self.reverse:
                    # Reverse the direction for destroy operations
                    self.dependency_graph.add_edge(dep, component)
                else:
                    # Normal direction for apply operations
                    self.dependency_graph.add_edge(component, dep)
        
        # Update class-level cache
        with self._cache_lock:
            self._dependency_graph_cache[self.cache_key] = self.dependency_graph.copy()
        
        logger.info(f"Built dependency graph with {len(components)} nodes and {self.dependency_graph.number_of_edges()} edges")
        return self.dependency_graph
    
    def _handle_cycles(self, graph: nx.DiGraph) -> nx.DiGraph:
        """Handle cycles in the dependency graph."""
        cycles = list(nx.simple_cycles(graph))
        if not cycles:
            return graph
        
        logger.warning(f"Found {len(cycles)} cycles in dependency graph")
        for cycle in cycles:
            cycle_str = " -> ".join(cycle) + " -> " + cycle[0]
            logger.warning(f"Cycle: {cycle_str}")
            
            # Break cycle by removing the last edge
            if len(cycle) > 1:
                edge_to_remove = (cycle[-1], cycle[0])
                if graph.has_edge(*edge_to_remove):
                    logger.info(f"Breaking cycle by removing dependency: {edge_to_remove[0]} -> {edge_to_remove[1]}")
                    graph.remove_edge(*edge_to_remove)
        
        # Verify all cycles are broken
        remaining_cycles = list(nx.simple_cycles(graph))
        if remaining_cycles:
            logger.error(f"Failed to break all cycles. {len(remaining_cycles)} cycles remain.")
        
        return graph
    
    def get_ordered_components(self) -> List[str]:
        """Get components in dependency order."""
        graph = self.build_dependency_graph()
        
        # Handle cycles if present
        graph = self._handle_cycles(graph)
        
        try:
            # Use topological sort to get order
            ordered = list(nx.topological_sort(graph))
            logger.info(f"Components ordered: {', '.join(ordered)}")
            return ordered
        except nx.NetworkXUnfeasible:
            logger.error("Cannot determine component order: graph contains cycles")
            # Fallback to original order if topological sort fails
            return self.get_components()


    @classmethod
    def clear_cache(cls, stack: Optional[str] = None) -> None:
        """
        Clear the class-level caches.
        
        Args:
            stack: If provided, only clear cache for this stack. If None, clear all caches.
        """
        with cls._cache_lock:
            if stack:
                if stack in cls._component_cache:
                    del cls._component_cache[stack]
                if stack in cls._config_cache:
                    del cls._config_cache[stack]
                
                # Clear graph caches with matching stack prefix
                keys_to_delete = []
                for key in cls._dependency_graph_cache:
                    if key.startswith(f"{stack}:"):
                        keys_to_delete.append(key)
                        
                for key in keys_to_delete:
                    del cls._dependency_graph_cache[key]
                    
                logger.debug(f"Cleared cache for stack {stack}")
            else:
                cls._component_cache.clear()
                cls._config_cache.clear()
                cls._dependency_graph_cache.clear()
                logger.debug("Cleared all component discovery caches")


def discover_and_order_components(stack: str, reverse: bool = False) -> List[str]:
    """
    Discover components and order them based on dependencies.
    
    Uses a lock to prevent race conditions in concurrent environments.
    
    Args:
        stack: The stack to discover components for
        reverse: Whether to reverse the dependency order (for destroy operations)
        
    Returns:
        List of components in dependency order
    """
    with discovery_lock:
        logger.debug(f"Acquired lock for component discovery on stack {stack}")
        discovery = ComponentDiscovery(stack, reverse)
        ordered_components = discovery.get_ordered_components()
        logger.debug(f"Releasing lock for component discovery on stack {stack}")
        return ordered_components