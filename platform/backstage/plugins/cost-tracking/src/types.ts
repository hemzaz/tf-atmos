export interface ResourceCost {
  id: string;
  name: string;
  service: string;
  region: string;
  cost: number;
  currency: string;
  period: string;
  tags: Record<string, string>;
  lastUpdated: string;
}

export interface CostTrend {
  date: string;
  cost: number;
  forecast?: number;
}

export interface CostAnalysis {
  totalCost: number;
  currency: string;
  period: string;
  trend: CostTrend[];
  breakdown: {
    byService: Array<{ service: string; cost: number; percentage: number }>;
    byEnvironment: Array<{ environment: string; cost: number; percentage: number }>;
    byProject: Array<{ project: string; cost: number; percentage: number }>;
  };
  budgets: Array<{
    name: string;
    limit: number;
    spent: number;
    remaining: number;
    alertThreshold: number;
  }>;
  recommendations: Array<{
    type: 'optimization' | 'rightsizing' | 'termination';
    resource: string;
    description: string;
    potentialSavings: number;
    confidence: 'high' | 'medium' | 'low';
  }>;
}