# Alexandria CLI - Command-Line Interface Specification

**Version:** 1.0.0
**Last Updated:** December 2, 2025

---

## Overview

The Alexandria CLI is the primary interface for discovering, managing, and deploying modules from the Alexandria Library. It provides a rich command-line experience with search, browse, recommendations, and lifecycle management capabilities.

---

## Installation

```bash
# Install from source
cd bin/alexandria
pip install -e .

# Or use npm (Node.js wrapper)
npm install -g @yourorg/alexandria-cli

# Or download binary
curl -L https://github.com/yourorg/alexandria/releases/latest/download/alexandria-$(uname -s)-$(uname -m) -o /usr/local/bin/alexandria
chmod +x /usr/local/bin/alexandria
```

---

## Global Options

Available for all commands:

```bash
--help, -h          Show help message
--version, -v       Show version
--config FILE       Path to config file (default: ~/.alexandria/config.yaml)
--output FORMAT     Output format: table, json, yaml, tree (default: table)
--color WHEN        When to use color: always, never, auto (default: auto)
--verbose, -vv      Enable verbose output
--quiet, -q         Suppress non-essential output
--no-pager          Disable paging for long output
```

---

## Commands

### 1. `search` - Search for modules

Search the module catalog using various criteria.

#### Usage

```bash
alexandria search [QUERY] [OPTIONS]
```

#### Examples

```bash
# Simple text search
alexandria search "vpc"
alexandria search "kubernetes cluster"

# Search with filters
alexandria search --category compute/containers
alexandria search --tags "serverless,api"
alexandria search --maturity stable
alexandria search "database" --complexity beginner

# Cost-based search
alexandria search --cost-max 100
alexandria search --cost-range "0-50"
alexandria search --cost-category low

# Multiple criteria
alexandria search "vpc multi-az" \
  --maturity stable \
  --cost-max 200 \
  --complexity intermediate

# Compliance search
alexandria search --compliance "HIPAA,PCI DSS"

# Trending and popular
alexandria search --sort trending --timeframe 30d
alexandria search --sort popular --limit 10
```

#### Options

```bash
# Filters
--category CAT        Filter by category (e.g., compute/containers)
--tags TAG[,TAG...]   Filter by tags (comma-separated)
--maturity LEVEL      Filter by maturity: experimental, alpha, beta, stable, mature
--complexity LEVEL    Filter by complexity: beginner, intermediate, advanced
--cost-min AMOUNT     Minimum monthly cost in USD
--cost-max AMOUNT     Maximum monthly cost in USD
--cost-range RANGE    Cost range: "0-50", "50-200", "200-1000", "1000+"
--cost-category CAT   Cost category: free, low, medium, high, very-high
--compliance STD      Filter by compliance standards

# Sorting
--sort FIELD          Sort by: name, downloads, rating, last_updated, cost, trending
--order ORDER         Sort order: asc, desc (default: desc for metrics, asc for name)

# Output
--limit N             Maximum results to show (default: 20)
--offset N            Skip first N results (default: 0)
--format FORMAT       Output format: table, json, yaml, compact
--show-details        Show detailed information
--show-cost           Include cost breakdown
--show-metrics        Include metrics (downloads, ratings, etc.)

# Advanced
--compatible-with ID  Show only modules compatible with given module
--requires ID         Show modules that require given module
--fuzzy              Enable fuzzy matching
--exact              Exact match only
```

#### Output

**Table format (default):**
```
┌─────────────────┬─────────────┬──────────┬────────────┬──────────┬─────────────────────────────────┐
│ Module          │ Maturity    │ Category │ Complexity │ Cost/mo  │ Description                     │
├─────────────────┼─────────────┼──────────┼────────────┼──────────┼─────────────────────────────────┤
│ vpc-standard    │ Mature ✓    │ Found... │ Inter...   │ $150     │ Production-ready VPC with...    │
│ vpc-basic       │ Stable ✓    │ Found... │ Beginner   │ $20      │ Simple VPC with 1-2 AZs...      │
│ vpc-advanced    │ Stable ✓    │ Found... │ Advanced   │ $300     │ Enterprise VPC with all...      │
└─────────────────┴─────────────┴──────────┴────────────┴──────────┴─────────────────────────────────┘

Found 3 modules matching your query. Use --show-details for more information.
```

**JSON format:**
```json
{
  "query": "vpc",
  "total_results": 3,
  "showing": 3,
  "modules": [
    {
      "id": "vpc-standard",
      "name": "Standard VPC",
      "maturity": "mature",
      "category": "foundations/networking",
      "complexity": "intermediate",
      "estimated_cost": 150,
      "rating": 4.8,
      "downloads": 1250
    }
  ]
}
```

---

### 2. `browse` - Browse module catalog

Interactive catalog browser with hierarchical navigation.

#### Usage

```bash
alexandria browse [CATEGORY] [OPTIONS]
```

#### Examples

```bash
# Browse all categories
alexandria browse

# Browse specific category
alexandria browse foundations
alexandria browse compute/containers

# Non-interactive listing
alexandria browse --list
alexandria browse foundations/networking --list

# Browse with filters
alexandria browse --maturity stable
alexandria browse compute --complexity beginner
```

#### Options

```bash
--list              Non-interactive list mode
--tree              Show as tree structure
--maturity LEVEL    Filter by maturity
--complexity LEVEL  Filter by complexity
--show-counts       Show module counts per category
--depth N           Maximum tree depth (default: unlimited)
```

#### Interactive Mode

```
Alexandria Library Browser
─────────────────────────────────────────────────────────────

 Foundations (12 modules)
   ├─ Networking (7)
   │  ├─ vpc-basic
   │  ├─ vpc-standard ⭐
   │  ├─ vpc-advanced
   │  ├─ dns
   │  └─ ...
   ├─ Security (3)
   └─ Identity (2)

 Compute (15 modules)
   ├─ Containers (8)
   ├─ Serverless (4)
   └─ Virtual Machines (3)

 Data (10 modules)
   ├─ Databases (5)
   ├─ Caching (3)
   └─ Storage (2)

Navigation: ↑↓ to move, → to expand, ← to collapse, Enter to select, q to quit
```

---

### 3. `info` - Show detailed module information

Display comprehensive information about a specific module.

#### Usage

```bash
alexandria info MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Basic info
alexandria info vpc-standard

# With specific sections
alexandria info vpc-standard --show-examples
alexandria info vpc-standard --show-cost
alexandria info vpc-standard --show-metrics
alexandria info vpc-standard --show-dependencies

# Full details
alexandria info vpc-standard --full
```

#### Options

```bash
--show-examples       Show usage examples
--show-cost          Show cost breakdown
--show-metrics       Show metrics and statistics
--show-dependencies  Show dependencies and compatible modules
--show-security      Show security scan results
--show-testing       Show test coverage and results
--full               Show all sections
--format FORMAT      Output format: text, json, yaml
```

#### Output

```
┌──────────────────────────────────────────────────────────────┐
│ Standard VPC                                                  │
│ Production-ready VPC with 2-3 AZs, NAT, and VPC endpoints   │
└──────────────────────────────────────────────────────────────┘

 Module ID:        vpc-standard
 Version:          2.1.0
 Maturity:         Mature ✓
 Category:         Foundations → Networking
 Complexity:       Intermediate
 Setup Time:       ~15 minutes

 Estimated Cost:   $150/month
   ├─ NAT Gateways (3x):    $97
   ├─ VPC Endpoints:        $36
   ├─ Flow Logs:            $10
   └─ Data Transfer:        $7

 Features:
   ✓ 2-3 Availability Zones
   ✓ Public, private, and database subnets
   ✓ NAT Gateway per AZ (high availability)
   ✓ VPC Endpoints (S3, DynamoDB, ECR, etc.)
   ✓ IPv6 support (optional)
   ✓ VPC Flow Logs
   ✓ DNS support and resolution

 Metrics:
   Downloads:         1,250
   Rating:            4.8/5.0 (156 reviews)
   Active Deploy.:    428
   Last Updated:      2025-11-30

 Dependencies:
   Terraform:         >= 1.5.0
   AWS Provider:      >= 5.0.0, < 6.0.0

 Compatible With:
   • eks-standard       • rds-postgres
   • ecs-fargate       • lambda-advanced

 Security:
   ✓ Checkov Passing    ✓ tfsec Passing
   ✓ Terrascan Passing  ✓ 0 Vulnerabilities
   Compliance: CIS AWS Foundations, HIPAA, PCI DSS

 Examples:
   ./examples/complete   - Full-featured VPC with all options
   ./examples/basic      - Standard VPC with sensible defaults
   ./examples/multi-reg  - Multi-region VPC with peering

 Documentation:
   README:      ./README.md
   Changelog:   ./CHANGELOG.md
   Architecture: ./docs/architecture.png

 Maintainer:
   Team:    Platform Engineering
   Contact: platform-team@example.com
   Support: #platform-support (24h SLA)

─────────────────────────────────────────────────────────────

Use 'alexandria deploy vpc-standard' to deploy this module
Use 'alexandria recommend --based-on vpc-standard' for suggestions
```

---

### 4. `recommend` - Get module recommendations

Get personalized module recommendations based on various criteria.

#### Usage

```bash
alexandria recommend [OPTIONS]
```

#### Examples

```bash
# Recommendations for a use case
alexandria recommend --for "microservices architecture"
alexandria recommend --for "web application with database"

# Recommendations based on a module
alexandria recommend --based-on vpc-standard
alexandria recommend --based-on eks-standard

# Recommendations for current stack
alexandria recommend --from-stack ./stack.yaml

# Complementary modules
alexandria recommend --complement vpc-standard,eks-standard

# Trending recommendations
alexandria recommend --trending --timeframe 30d
```

#### Options

```bash
--for USE_CASE         Recommend for a use case
--based-on MODULE      Similar to given module
--complement MODULES   Complementary modules (comma-separated)
--from-stack FILE      Analyze stack and recommend
--trending             Show trending modules
--timeframe DAYS       Timeframe for trending (default: 30d)
--limit N              Maximum recommendations (default: 5)
--show-reason          Show recommendation reasoning
--min-score SCORE      Minimum similarity score (0-1, default: 0.6)
```

#### Output

```
Top 5 Recommendations for "microservices architecture"
─────────────────────────────────────────────────────────────

1. eks-standard (⭐ 4.9/5.0)
   Production-ready EKS cluster with managed node groups
   Reason: Core platform for microservices
   Cost: $450/mo | Complexity: Advanced
   → alexandria info eks-standard

2. vpc-standard (⭐ 4.8/5.0)
   Production-ready VPC with 2-3 AZs, NAT, and VPC endpoints
   Reason: Required networking foundation
   Cost: $150/mo | Complexity: Intermediate
   → alexandria info vpc-standard

3. monitoring (⭐ 4.8/5.0)
   CloudWatch monitoring with dashboards and alarms
   Reason: Essential observability for microservices
   Cost: $45/mo | Complexity: Intermediate
   → alexandria info monitoring

4. apigateway-rest (⭐ 4.7/5.0)
   REST API Gateway with authentication and custom domains
   Reason: API management for service mesh
   Cost: $50/mo | Complexity: Intermediate
   → alexandria info apigateway-rest

5. secretsmanager (⭐ 4.7/5.0)
   Secrets management with rotation and access control
   Reason: Secure configuration management
   Cost: $1.20/mo | Complexity: Intermediate
   → alexandria info secretsmanager

─────────────────────────────────────────────────────────────
Total estimated cost: ~$696/month

Use 'alexandria blueprint create microservices' to generate a complete stack
```

---

### 5. `compare` - Compare modules

Compare multiple modules side-by-side.

#### Usage

```bash
alexandria compare MODULE1 MODULE2 [MODULE3...] [OPTIONS]
```

#### Examples

```bash
# Compare VPC modules
alexandria compare vpc-basic vpc-standard vpc-advanced

# Compare with specific aspects
alexandria compare eks-standard ecs-fargate --aspects cost,features,complexity

# JSON output for automation
alexandria compare vpc-basic vpc-standard --format json
```

#### Options

```bash
--aspects ASPECTS     What to compare: cost, features, complexity, performance, all
--format FORMAT       Output format: table, json, yaml
--show-differences    Show only differences
--highlight-best      Highlight best option for each metric
```

#### Output

```
Module Comparison
─────────────────────────────────────────────────────────────────────────────────────

                     vpc-basic          vpc-standard       vpc-advanced
─────────────────────────────────────────────────────────────────────────────────────
Maturity             Stable ✓           Mature ⭐          Stable ✓
Complexity           Beginner           Intermediate       Advanced
Setup Time           5 min              15 min             30 min
Variables            10                 35                 65

Cost/month           $20 🏆            $150               $300
├─ NAT Gateways      $16 (1x)          $97 (3x)           $194 (6x)
├─ VPC Endpoints     N/A               $36                $72
└─ Flow Logs         $4                $10                $20

Features
├─ Availability Zones  1-2              2-3 ✓              3-6
├─ NAT Gateways       Single            Per AZ ✓           Per AZ + backup
├─ VPC Endpoints      No                Standard ✓         All + PrivateLink
├─ IPv6 Support       No                Optional ✓         Full ✓
├─ Flow Logs          Basic             Standard ✓         Advanced ✓
└─ Transit Gateway    No                No                 Yes ✓

Performance
├─ Deployment Time    300s 🏆           900s               1800s
├─ Resource Count     15 🏆             85                 200
└─ State Size         45 KB 🏆          320 KB             680 KB

Metrics
├─ Downloads          450               1,250 🏆           320
├─ Rating             4.5               4.8 🏆             4.6
└─ Active Deploys     145               428 🏆             98

Best For:
vpc-basic:      Dev/test environments, proof of concept, training
vpc-standard:   Production workloads, multi-tier apps, compliance 🏆
vpc-advanced:   Enterprise, multi-region, complex networking

─────────────────────────────────────────────────────────────────────────────────────
🏆 = Best in category
```

---

### 6. `versions` - Show module versions

List all available versions of a module.

#### Usage

```bash
alexandria versions MODULE_ID [OPTIONS]
```

#### Examples

```bash
# List all versions
alexandria versions vpc-standard

# Show version details
alexandria versions vpc-standard --detailed

# Filter by maturity
alexandria versions vpc-standard --maturity stable

# Show changelog
alexandria versions vpc-standard --changelog
```

#### Options

```bash
--detailed          Show detailed version information
--changelog         Show changelog for each version
--maturity LEVEL    Filter by maturity level
--limit N           Maximum versions to show
```

---

### 7. `dependencies` - Show module dependencies

Visualize module dependencies and compatibility.

#### Usage

```bash
alexandria dependencies MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Show dependencies
alexandria dependencies eks-standard

# Show as graph
alexandria dependencies eks-standard --graph

# Show full dependency tree
alexandria dependencies eks-standard --tree --recursive

# Check compatibility
alexandria dependencies eks-standard --check-compatible vpc-basic
```

#### Options

```bash
--graph             Show as visual graph
--tree              Show as tree structure
--recursive         Include transitive dependencies
--check-compatible  Check compatibility with another module
--output FILE       Export graph to file (png, svg, dot)
```

---

### 8. `cost` - Estimate module cost

Calculate estimated costs for a module or stack.

#### Usage

```bash
alexandria cost MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Estimate single module cost
alexandria cost vpc-standard

# With specific parameters
alexandria cost vpc-standard --region us-west-2 --param nat_gateways=2

# Cost for entire stack
alexandria cost --stack ./stack.yaml

# Compare costs across regions
alexandria cost vpc-standard --compare-regions us-east-1,us-west-2,eu-west-1

# What-if analysis
alexandria cost eks-standard --param node_count=5 --param instance_type=t3.large
```

#### Options

```bash
--region REGION         AWS region for pricing (default: us-east-1)
--param KEY=VALUE       Override parameter values
--stack FILE            Estimate cost for entire stack
--compare-regions R     Compare costs across regions
--breakdown             Show detailed cost breakdown
--timeframe PERIOD      Cost period: monthly, yearly (default: monthly)
--format FORMAT         Output format: table, json, csv
```

---

### 9. `scaffold` - Create new module

Generate a new module with standard structure.

#### Usage

```bash
alexandria scaffold --name MODULE_NAME [OPTIONS]
```

#### Examples

```bash
# Create basic module
alexandria scaffold --name my-module \
  --category foundations/networking \
  --maturity experimental

# With template
alexandria scaffold --name my-api \
  --category integration/api-management \
  --template apigateway \
  --complexity intermediate

# Interactive mode
alexandria scaffold --interactive
```

#### Options

```bash
--name NAME             Module name (required)
--category CATEGORY     Module category (required)
--maturity LEVEL        Initial maturity level (default: experimental)
--complexity LEVEL      Complexity level (default: intermediate)
--template TEMPLATE     Use template (vpc, eks, rds, lambda, etc.)
--interactive, -i       Interactive mode
--output-dir DIR        Output directory (default: ./_library/...)
```

---

### 10. `validate` - Validate module

Validate a module against standards.

#### Usage

```bash
alexandria validate [MODULE_PATH] [OPTIONS]
```

#### Examples

```bash
# Validate module
alexandria validate ./my-module

# Strict validation
alexandria validate ./my-module --strict

# Specific checks
alexandria validate ./my-module --checks structure,naming,security

# Auto-fix issues
alexandria validate ./my-module --fix
```

#### Options

```bash
--strict                Strict validation mode
--checks CHECKS         Specific checks: structure, naming, security, docs, testing
--fix                   Auto-fix issues where possible
--output-format FORMAT  Output format: text, json, junit
```

---

### 11. `test` - Test module

Run module tests.

#### Usage

```bash
alexandria test [MODULE_PATH] [OPTIONS]
```

#### Examples

```bash
# Run all tests
alexandria test ./my-module

# Specific test types
alexandria test ./my-module --unit
alexandria test ./my-module --integration

# With coverage
alexandria test ./my-module --coverage

# Specific test
alexandria test ./my-module --test test_vpc_creation
```

#### Options

```bash
--unit              Run unit tests only
--integration       Run integration tests only
--coverage          Generate coverage report
--test TEST_NAME    Run specific test
--parallel N        Run N tests in parallel
--timeout SECONDS   Test timeout (default: 1800)
```

---

### 12. `register` - Register module in catalog

Register a module in the Alexandria catalog.

#### Usage

```bash
alexandria register MODULE_PATH [OPTIONS]
```

#### Examples

```bash
# Register module
alexandria register ./my-module \
  --version 1.0.0 \
  --maturity beta

# With tags
alexandria register ./my-module \
  --version 1.0.0 \
  --tags "vpc,networking,multi-az"

# Dry run
alexandria register ./my-module --version 1.0.0 --dry-run
```

#### Options

```bash
--version VERSION       Module version (required)
--maturity LEVEL        Maturity level
--tags TAGS             Tags (comma-separated)
--dry-run               Validate without registering
--force                 Force registration (skip some checks)
```

---

### 13. `publish` - Publish module

Publish a module to make it available.

#### Usage

```bash
alexandria publish MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Publish module
alexandria publish my-module

# Publish specific version
alexandria publish my-module --version 1.0.0

# With release notes
alexandria publish my-module --notes "Added IPv6 support"
```

---

### 14. `deprecate` - Deprecate module

Mark a module as deprecated.

#### Usage

```bash
alexandria deprecate MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Deprecate module
alexandria deprecate old-vpc \
  --replacement vpc-standard \
  --removal-date 2026-06-01 \
  --reason "Superseded by vpc-standard"

# Generate migration guide
alexandria deprecate old-vpc \
  --replacement vpc-standard \
  --generate-migration-guide
```

---

### 15. `stats` - Show module statistics

Display statistics and analytics for a module.

#### Usage

```bash
alexandria stats MODULE_ID [OPTIONS]
```

#### Examples

```bash
# Basic stats
alexandria stats vpc-standard

# Detailed analytics
alexandria stats vpc-standard --detailed

# Time-series data
alexandria stats vpc-standard --timeframe 90d --chart

# Export data
alexandria stats vpc-standard --export stats.json
```

---

### 16. `popular` - Show popular modules

List popular modules by various metrics.

#### Usage

```bash
alexandria popular [OPTIONS]
```

#### Examples

```bash
# Most popular overall
alexandria popular

# Popular in category
alexandria popular --category compute

# Trending
alexandria popular --trending --timeframe 30d

# Top rated
alexandria popular --sort rating --limit 10
```

---

### 17. `trending` - Show trending modules

Show modules with growing popularity.

#### Usage

```bash
alexandria trending [OPTIONS]
```

#### Examples

```bash
# Trending modules
alexandria trending

# Specific timeframe
alexandria trending --timeframe 7d
alexandria trending --timeframe 30d

# By category
alexandria trending --category security
```

---

### 18. `config` - Manage CLI configuration

Configure the Alexandria CLI.

#### Usage

```bash
alexandria config [COMMAND] [OPTIONS]
```

#### Examples

```bash
# Show current config
alexandria config show

# Set configuration value
alexandria config set output.format json
alexandria config set search.default_limit 50

# Get configuration value
alexandria config get output.format

# Reset to defaults
alexandria config reset

# Edit config file
alexandria config edit
```

---

### 19. `update` - Update CLI and index

Update the Alexandria CLI and module index.

#### Usage

```bash
alexandria update [OPTIONS]
```

#### Examples

```bash
# Update CLI and index
alexandria update

# Update index only
alexandria update --index-only

# Update CLI only
alexandria update --cli-only

# Check for updates
alexandria update --check
```

---

## Configuration File

Location: `~/.alexandria/config.yaml`

```yaml
# Alexandria CLI Configuration

# Output preferences
output:
  format: "table"        # table, json, yaml
  color: "auto"          # always, never, auto
  paging: true           # Enable paging for long output

# Search preferences
search:
  default_limit: 20
  default_maturity: ["stable", "mature"]
  fuzzy_matching: true
  show_cost: true
  show_metrics: true

# Display preferences
display:
  show_icons: true
  compact_mode: false
  datetime_format: "2006-01-02"

# API settings
api:
  endpoint: "https://alexandria.yourorg.com/api/v1"
  timeout: 30
  retries: 3

# Cache settings
cache:
  enabled: true
  ttl_hours: 24
  path: "~/.alexandria/cache"

# User preferences
user:
  expertise_level: "intermediate"  # beginner, intermediate, advanced
  preferred_complexity: ["beginner", "intermediate"]
  cost_sensitivity: "medium"       # low, medium, high

# Telemetry (anonymous usage statistics)
telemetry:
  enabled: true
  anonymous: true
```

---

## Environment Variables

```bash
ALEXANDRIA_CONFIG       # Config file path
ALEXANDRIA_OUTPUT       # Default output format
ALEXANDRIA_NO_COLOR     # Disable color output
ALEXANDRIA_NO_PAGER     # Disable paging
ALEXANDRIA_API_ENDPOINT # API endpoint URL
ALEXANDRIA_LOG_LEVEL    # Log level: debug, info, warn, error
```

---

## Exit Codes

```
0   Success
1   General error
2   Invalid arguments
3   Module not found
4   Validation failed
5   Test failed
6   Network error
7   Authentication error
8   Permission denied
10  Internal error
```

---

## Shell Completion

```bash
# Bash
alexandria completion bash > /etc/bash_completion.d/alexandria

# Zsh
alexandria completion zsh > /usr/local/share/zsh/site-functions/_alexandria

# Fish
alexandria completion fish > ~/.config/fish/completions/alexandria.fish
```

---

## Advanced Usage

### Piping and Scripting

```bash
# Get module IDs as JSON
alexandria search "vpc" --format json | jq '.modules[].id'

# Find all stable modules
alexandria browse --list --maturity stable --format json

# Cost analysis for multiple modules
for module in vpc-standard eks-standard rds-postgres; do
  alexandria cost $module --format json
done | jq -s 'map(.estimated_monthly_usd) | add'

# Batch validation
find ./_library -name ".alexandria.yaml" -exec dirname {} \; | \
  xargs -I {} alexandria validate {}
```

### Integration with Atmos

```bash
# Generate Atmos stack from Alexandria modules
alexandria blueprint create web-app --format atmos > stacks/myapp.yaml

# Validate Atmos stack against catalog
alexandria validate-stack --stack stacks/myapp.yaml
```

---

## Future Enhancements

- **TUI (Terminal UI):** Interactive full-screen interface
- **Web Dashboard:** Browser-based module explorer
- **IDE Integration:** VSCode/IntelliJ plugins
- **CI/CD Integration:** GitHub Actions, GitLab CI templates
- **Slack/Teams Bots:** Search modules from chat
- **AI Assistant:** Natural language module discovery

---

## Support

- Documentation: https://docs.yourorg.com/alexandria
- Issues: https://github.com/yourorg/alexandria/issues
- Slack: #alexandria-support
- Email: platform-team@yourorg.com
