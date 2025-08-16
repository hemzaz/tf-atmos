/**
 * Atmos plugin types for Backstage integration
 */

export interface AtmosStack {
  name: string;
  tenant: string;
  account: string;
  environment: string;
  region: string;
  components: string[];
  variables: Record<string, any>;
  metadata: Record<string, any>;
}

export interface AtmosComponent {
  name: string;
  type: 'terraform' | 'helmfile' | 'spacelift';
  path: string;
  description: string;
  variables: Record<string, any>;
  outputs: Record<string, any>;
  metadata: Record<string, any>;
}

export interface AtmosWorkflow {
  name: string;
  description: string;
  steps: WorkflowStep[];
  file: string;
  metadata: Record<string, any>;
}

export interface WorkflowStep {
  name?: string;
  command?: string;
  run?: string;
  type?: string;
  description?: string;
  condition?: string;
}

export interface WorkflowExecutionRequest {
  workflow: string;
  stack?: string;
  parameters?: Record<string, string>;
  dryRun?: boolean;
  timeout?: number;
}

export interface WorkflowExecutionResult {
  workflow: string;
  status: 'success' | 'error' | 'pending';
  output: string;
  error?: string;
  executionTime: number;
  timestamp: string;
}

export interface StackValidationResult {
  stack: string;
  valid: boolean;
  errors: string[];
  warnings: string[];
  timestamp: string;
}

export interface ComponentValidationResult {
  component: string;
  stack?: string;
  valid: boolean;
  errors: string[];
  warnings: string[];
  timestamp: string;
}

export interface AtmosConfig {
  version: string;
  components: {
    terraform?: {
      base_path?: string;
      apply_auto_approve?: boolean;
      deploy_run_init?: boolean;
      init_run_reconfigure?: boolean;
      auto_generate_backend_file?: boolean;
    };
    helmfile?: {
      base_path?: string;
      kubeconfig_path?: string;
      helm_aws_profile_pattern?: string;
      cluster_name_pattern?: string;
    };
  };
  stacks: {
    base_path?: string;
    included_paths?: string[];
    excluded_paths?: string[];
    name_pattern?: string;
  };
  workflows: {
    base_path?: string;
  };
  integrations?: {
    github?: {
      gitops_repo?: string;
      gitops_branch?: string;
    };
    spacelift?: {
      workspace_enabled?: boolean;
      workspace_description_pattern?: string;
    };
  };
}

export interface ServiceRequest {
  serviceName: string;
  template: string;
  tenant: string;
  account: string;
  environment: string;
  region?: string;
  parameters: Record<string, any>;
  metadata?: Record<string, any>;
}

export interface ServiceResponse {
  serviceName: string;
  status: 'provisioning' | 'ready' | 'error';
  stack: string;
  components: string[];
  endpoints?: string[];
  cost?: {
    monthly: number;
    currency: string;
  };
  timestamp: string;
}

export interface CostEstimate {
  component: string;
  resourceType: string;
  monthlyCost: number;
  currency: string;
  breakdown: CostBreakdown[];
}

export interface CostBreakdown {
  resource: string;
  quantity: number;
  unitCost: number;
  monthlyCost: number;
}

export interface ComplianceCheck {
  check: string;
  status: 'pass' | 'fail' | 'warning';
  message: string;
  severity: 'low' | 'medium' | 'high' | 'critical';
  component?: string;
  stack?: string;
}

export interface PlatformMetrics {
  stacks: {
    total: number;
    healthy: number;
    unhealthy: number;
  };
  components: {
    total: number;
    deployed: number;
    failed: number;
  };
  workflows: {
    total: number;
    successful: number;
    failed: number;
    lastRun: string;
  };
  cost: {
    monthly: number;
    trending: 'up' | 'down' | 'stable';
    currency: string;
  };
  compliance: {
    score: number;
    checks: number;
    passed: number;
    failed: number;
  };
}