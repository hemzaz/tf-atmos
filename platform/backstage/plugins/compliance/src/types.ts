export interface ComplianceRule {
  id: string;
  name: string;
  description: string;
  framework: 'SOC2' | 'PCI-DSS' | 'HIPAA' | 'GDPR' | 'ISO27001' | 'CIS' | 'NIST';
  severity: 'critical' | 'high' | 'medium' | 'low';
  category: 'access-control' | 'encryption' | 'monitoring' | 'network' | 'data-protection';
  automated: boolean;
  lastChecked: string;
  status: 'compliant' | 'non-compliant' | 'warning' | 'unknown';
  remediation?: string;
}

export interface PolicyViolation {
  id: string;
  ruleId: string;
  resource: string;
  resourceType: string;
  environment: string;
  description: string;
  severity: 'critical' | 'high' | 'medium' | 'low';
  detectedAt: string;
  status: 'open' | 'acknowledged' | 'resolved' | 'suppressed';
  assignee?: string;
  dueDate?: string;
  remediation: string;
  evidence?: {
    type: 'screenshot' | 'log' | 'config' | 'scan-result';
    content: string;
    url?: string;
  }[];
}

export interface SecurityPosture {
  overallScore: number;
  maxScore: number;
  lastAssessment: string;
  trends: Array<{
    date: string;
    score: number;
  }>;
  frameworks: Array<{
    name: string;
    score: number;
    maxScore: number;
    status: 'compliant' | 'non-compliant' | 'partial';
    requirements: {
      total: number;
      compliant: number;
      nonCompliant: number;
      notApplicable: number;
    };
  }>;
  categories: Array<{
    category: string;
    score: number;
    maxScore: number;
    rulesTotal: number;
    rulesCompliant: number;
  }>;
  criticalViolations: number;
  highViolations: number;
  mediumViolations: number;
  lowViolations: number;
}