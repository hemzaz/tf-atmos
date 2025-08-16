# Task Hygiene Analyzer

Analyze and optimize project backlogs in $ARGUMENTS by identifying duplicates, consolidating related tasks, and reorganizing for maximum efficiency.

## Task

I'll perform comprehensive task hygiene analysis including:

1. Multi-format task discovery and parsing
2. Semantic duplicate detection and consolidation
3. Priority assessment and effort estimation
4. Sprint-ready backlog reorganization
5. Actionable cleanup recommendations with metrics

## Process

I'll follow these steps:

1. Scan target files/directories for task content
2. Parse tasks from multiple formats (markdown, JSON, YAML, GitHub issues)
3. Analyze task relationships and identify duplicates
4. Assess priority, complexity, and dependencies
5. Generate optimization recommendations and reorganized structure
6. Provide before/after metrics and implementation guidance

## Analysis Types

### Task Discovery
- Todo lists in markdown files (- [ ], TODO:, FIXME:)
- JSON/YAML project management exports
- GitHub Issues and Pull Request comments
- Jira export files and CSV formats
- Code comments with task indicators

### Duplicate Detection
- Semantic similarity analysis using keyword matching
- Intent-based grouping (similar goals/outcomes)
- Cross-format duplicate identification
- Partial overlap detection (sub-tasks vs main tasks)
- Context-aware clustering by project area

### Task Assessment
- Complexity scoring based on description keywords
- Priority inference from language patterns
- Effort estimation using historical patterns
- Dependency identification through reference analysis
- Staleness detection for outdated tasks

## Optimization Features

### Consolidation Strategies
- **Conservative**: Only merge obvious exact duplicates
- **Standard**: Group semantically similar tasks with confidence threshold
- **Aggressive**: Consolidate all related tasks into epics with sub-tasks
- **Interactive**: Prompt for consolidation decisions with explanations

### Reorganization Patterns
- Epic creation for related task clusters
- Sprint-sized work item grouping
- Dependency-aware task ordering
- Priority-based backlog structuring
- Technical debt vs feature work separation

### Quality Metrics
- Task clarity and actionability scores
- Acceptance criteria completeness
- Effort estimation confidence levels
- Dependency complexity analysis
- Backlog health indicators

## Output Formats

### Markdown Report
```markdown
# Task Hygiene Analysis Report

## Summary
- Total tasks analyzed: 147
- Duplicates identified: 23
- Consolidation opportunities: 8 epics
- Recommended removals: 12 tasks
- Effort reduction: 15% through deduplication

## Findings
### Duplicate Clusters
1. **Authentication System** (5 tasks → 1 epic)
2. **API Documentation** (3 tasks → consolidated)

### Cleanup Recommendations
- Remove 7 completed tasks still marked as open
- Archive 5 outdated/obsolete requirements
```

### Interactive Mode
- Step-by-step consolidation prompts
- Visual task relationship graphs
- Real-time effort impact calculations
- Bulk action confirmations
- Undo/redo capability for changes

### JSON/YAML Export
- Structured data for integration with project management tools
- GitHub Issues import format
- Jira CSV export compatibility
- Custom schema support for various tools

## Best Practices

### Analysis Guidelines
- Preserve original task context and history
- Maintain traceability through consolidation
- Flag high-risk consolidations for manual review
- Respect existing priority and assignment systems
- Document rationale for all recommendations

### Quality Standards
- Ensure consolidated tasks maintain all original requirements
- Verify effort estimates align with team velocity
- Validate dependency relationships remain intact
- Confirm priority assignments reflect business value
- Check that no critical information is lost in consolidation

### Implementation Workflow
- Create backup of original task data
- Apply changes incrementally with validation
- Update related documentation and references
- Notify stakeholders of significant changes
- Schedule follow-up hygiene maintenance

I'll adapt to your project's task management system and provide actionable optimization recommendations with clear implementation steps.