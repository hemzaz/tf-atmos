# Alexandria Library - Module Catalog

This directory contains the searchable catalog and metadata for all Alexandria Library modules.

## Files

### `module-registry.yaml`
Master registry containing all module metadata including:
- Module identification (id, name, version)
- Classification (category, tags, maturity)
- Cost estimation and breakdown
- Metrics (downloads, ratings, deployments)
- Dependencies and compatibility
- Testing and security status
- Documentation references
- Maintainer information

**Usage:**
```bash
# View all modules
cat module-registry.yaml

# Search for specific module
yq '.modules[] | select(.id == "vpc-standard")' module-registry.yaml

# List all stable modules
yq '.modules[] | select(.maturity == "stable") | .id' module-registry.yaml
```

### `search-index.yaml`
Search and discovery system configuration defining:
- 12 search indices (full-text, category, tags, maturity, cost, etc.)
- Ranking algorithms
- Recommendation engine configuration
- Faceted search setup
- Auto-completion and suggestions
- Analytics and caching

**Usage:**
```bash
# Alexandria CLI uses this file automatically
alexandria search "vpc"
alexandria browse
alexandria recommend --for "microservices"
```

### `categories.yaml` (TODO)
Category hierarchy and descriptions:
- Foundations (Networking, Security, Identity)
- Compute (Containers, Serverless, Virtual Machines)
- Data (Databases, Caching, Storage)
- Integration (Messaging, API Management, Event Streaming)
- Observability (Logging, Metrics, Tracing)
- Security (Access Control, Secrets, Compliance)
- Patterns (Composite Solutions)

### `tags.yaml` (TODO)
Tag taxonomy and definitions:
- Infrastructure tags (vpc, eks, rds, etc.)
- Capability tags (multi-az, ha, serverless, etc.)
- Compliance tags (hipaa, pci-dss, soc2, etc.)
- Technology tags (terraform, kubernetes, docker, etc.)

### `maturity-levels.yaml` (TODO)
Maturity level definitions and requirements:
- Experimental: Early development
- Alpha: Feature development
- Beta: Feature complete
- Stable: Production ready
- Mature: Battle-tested
- Deprecated: Marked for removal

## Module Registry Schema

Each module entry follows this structure:

```yaml
- id: "module-id"                    # Unique identifier
  name: "Module Display Name"        # Human-readable name
  version: "1.0.0"                   # SemVer version
  maturity: "stable"                 # Maturity level
  category: "layer/function"         # Category path
  subcategory: "specific-type"       # Subcategory
  path: "relative/path"              # Module location

  description: "Short description"
  long_description: |
    Detailed multi-line description
    of module functionality

  tags:                              # Searchable tags
    - tag1
    - tag2

  complexity: "intermediate"         # beginner|intermediate|advanced
  setup_time_minutes: 15            # Estimated deployment time
  variable_count: 25                # Number of variables

  cost:                             # Cost information
    estimated_monthly_usd: 150
    cost_category: "medium"
    cost_factors:
      - "Factor 1"
      - "Factor 2"
    cost_breakdown:
      resource1: 100
      resource2: 50

  features:                         # Key features list
    - "Feature 1"
    - "Feature 2"

  use_cases:                        # Common use cases
    - "Use case 1"
    - "Use case 2"

  maintainer:                       # Ownership information
    team: "Team Name"
    primary: "email@example.com"
    backup: "backup@example.com"

  support:                          # Support details
    channel: "#channel"
    sla_hours: 24
    oncall: "oncall-alias"

  dependencies:                     # Requirements
    terraform_version: ">= 1.5.0"
    provider_versions:
      aws: ">= 5.0.0, < 6.0.0"
    required_modules: []

  compatible_with:                  # Compatible modules
    - "module-id-1"
    - "module-id-2"

  incompatible_with: []            # Incompatible modules
  replaces: []                     # Modules this replaces
  replaced_by: null                # Replacement module

  metrics:                         # Usage metrics
    downloads: 1000
    rating: 4.8
    rating_count: 100
    deployments: 500
    active_deployments: 450
    issues_open: 2
    issues_closed: 50
    last_updated: "2025-12-01"
    first_published: "2024-01-01"

  lifecycle:                       # Lifecycle information
    created: "2024-01-01"
    stabilized: "2024-06-01"
    deprecated: null
    removed: null
    replacement: null

  documentation:                   # Documentation links
    readme: "./README.md"
    changelog: "./CHANGELOG.md"
    architecture_diagram: "./docs/architecture.png"
    examples:
      - path: "./examples/complete"
        description: "Full example"
        complexity: "intermediate"

  testing:                         # Test status
    unit_tests: 15
    integration_tests: 5
    coverage_percent: 85
    last_test_run: "2025-12-01T10:00:00Z"
    test_status: "passing"
    test_duration_seconds: 300

  security:                        # Security status
    checkov_passing: true
    tfsec_passing: true
    terrascan_passing: true
    last_scan: "2025-12-01"
    vulnerabilities:
      critical: 0
      high: 0
      medium: 0
      low: 0
    compliance:
      - "CIS AWS Foundations"

  performance:                     # Performance metrics
    deployment_time_seconds: 900
    resource_count: 85
    state_size_kb: 320
```

## Maintaining the Catalog

### Adding a New Module

1. Add entry to `module-registry.yaml`:
   ```bash
   # Use Alexandria CLI
   alexandria register /path/to/module \
     --version 1.0.0 \
     --maturity alpha
   ```

2. Update will automatically:
   - Generate module ID
   - Set initial metrics
   - Update search index
   - Create catalog entry

### Updating Module Metadata

```bash
# Update specific fields
alexandria catalog update vpc-standard \
  --set maturity=stable \
  --set rating=4.9

# Refresh metrics from actual usage
alexandria catalog refresh-metrics vpc-standard

# Bulk update
alexandria catalog update --all --refresh-metrics
```

### Validating Catalog

```bash
# Validate entire catalog
alexandria catalog validate

# Check for:
# - Schema compliance
# - Broken references
# - Missing modules
# - Inconsistent data
```

## Search Index

The search index powers the Alexandria CLI discovery features.

### Rebuilding Search Index

```bash
# Full rebuild
alexandria search-index rebuild

# Incremental update
alexandria search-index update

# Optimize index
alexandria search-index optimize
```

### Search Index Structure

```yaml
indices:
  - name: "full_text"        # Text search across all fields
  - name: "category"         # Category browsing
  - name: "tags"             # Tag-based search
  - name: "maturity"         # Filter by maturity level
  - name: "cost"             # Cost-based filtering
  - name: "complexity"       # Complexity filtering
  - name: "popularity"       # Sort by popularity
  - name: "compatibility"    # Find compatible modules
  - name: "security"         # Security/compliance search
  - name: "performance"      # Performance filtering
```

## Statistics

Current catalog statistics (as of December 2, 2025):

- **Total Modules:** 22
- **Maturity Breakdown:**
  - Experimental: 0
  - Alpha: 0
  - Beta: 2
  - Stable: 17
  - Mature: 3
  - Deprecated: 0

- **Category Breakdown:**
  - Foundations: 7
  - Compute: 5
  - Data: 1
  - Integration: 3
  - Observability: 3
  - Security: 0
  - Operations: 3

- **Average Metrics:**
  - Downloads: 1,100
  - Rating: 4.7/5.0
  - Test Coverage: 85%
  - Active Deployments: 450

## API Access

The catalog can be accessed via:

1. **Alexandria CLI:**
   ```bash
   alexandria search "query"
   alexandria info module-id
   alexandria browse
   ```

2. **Direct YAML Access:**
   ```bash
   yq '.modules' module-registry.yaml
   ```

3. **REST API (Future):**
   ```bash
   curl https://alexandria.example.com/api/v1/modules
   curl https://alexandria.example.com/api/v1/modules/vpc-standard
   ```

4. **Python API (Future):**
   ```python
   from alexandria import Catalog

   catalog = Catalog()
   modules = catalog.search("vpc")
   vpc = catalog.get("vpc-standard")
   ```

## Contributing

To contribute to the catalog:

1. Follow [MODULE_STANDARDS.md](../../../docs/MODULE_STANDARDS.md)
2. Use [ALEXANDRIA_WORKFLOWS.md](../../../docs/ALEXANDRIA_WORKFLOWS.md)
3. Create module with proper metadata
4. Register via Alexandria CLI
5. Submit pull request

## Support

- **Documentation:** [LIBRARY_ARCHITECTURE.md](../../../docs/LIBRARY_ARCHITECTURE.md)
- **CLI Reference:** [ALEXANDRIA_CLI.md](../../../docs/ALEXANDRIA_CLI.md)
- **Workflows:** [ALEXANDRIA_WORKFLOWS.md](../../../docs/ALEXANDRIA_WORKFLOWS.md)
- **Support Channel:** #alexandria-support
- **Email:** platform-team@example.com

## License

Internal use only - Proprietary
