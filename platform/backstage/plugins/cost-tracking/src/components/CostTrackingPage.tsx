import React from 'react';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Chip,
  Alert,
  List,
  ListItem,
  ListItemText,
  ListItemIcon,
  Tooltip,
} from '@material-ui/core';
import {
  TrendingUp as TrendingUpIcon,
  TrendingDown as TrendingDownIcon,
  AttachMoney as MoneyIcon,
  Warning as WarningIcon,
  CheckCircle as CheckCircleIcon,
  Info as InfoIcon,
} from '@material-ui/icons';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip as RechartsTooltip,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
  ResponsiveContainer,
  Legend,
} from 'recharts';
import {
  Header,
  Page,
  Content,
  ContentHeader,
  SupportButton,
  Progress,
} from '@backstage/core-components';
import { useApi, configApiRef } from '@backstage/core-plugin-api';
import { useAsync } from 'react-use';
import { CostAnalysis } from '../types';

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042', '#8884D8', '#82CA9D'];

const mockCostData: CostAnalysis = {
  totalCost: 45623.47,
  currency: 'USD',
  period: 'monthly',
  trend: [
    { date: '2024-01', cost: 42000 },
    { date: '2024-02', cost: 43500 },
    { date: '2024-03', cost: 41200 },
    { date: '2024-04', cost: 44800 },
    { date: '2024-05', cost: 45623.47, forecast: 47000 },
  ],
  breakdown: {
    byService: [
      { service: 'EKS', cost: 18500, percentage: 40.5 },
      { service: 'RDS', cost: 12300, percentage: 27.0 },
      { service: 'S3', cost: 5400, percentage: 11.8 },
      { service: 'Lambda', cost: 4200, percentage: 9.2 },
      { service: 'Others', cost: 5223.47, percentage: 11.5 },
    ],
    byEnvironment: [
      { environment: 'Production', cost: 28500, percentage: 62.5 },
      { environment: 'Development', cost: 12000, percentage: 26.3 },
      { environment: 'Staging', cost: 5123.47, percentage: 11.2 },
    ],
    byProject: [
      { project: 'Core Platform', cost: 22000, percentage: 48.2 },
      { project: 'Analytics', cost: 15600, percentage: 34.2 },
      { project: 'ML Pipeline', cost: 8023.47, percentage: 17.6 },
    ],
  },
  budgets: [
    {
      name: 'Monthly Infrastructure',
      limit: 50000,
      spent: 45623.47,
      remaining: 4376.53,
      alertThreshold: 80,
    },
    {
      name: 'Development Environments',
      limit: 15000,
      spent: 12000,
      remaining: 3000,
      alertThreshold: 75,
    },
  ],
  recommendations: [
    {
      type: 'rightsizing',
      resource: 'RDS db.r5.2xlarge instances',
      description: 'Downsize underutilized database instances to db.r5.xlarge',
      potentialSavings: 2400,
      confidence: 'high',
    },
    {
      type: 'optimization',
      resource: 'EKS node groups',
      description: 'Switch to Spot instances for non-critical workloads',
      potentialSavings: 3200,
      confidence: 'medium',
    },
    {
      type: 'termination',
      resource: 'Unused S3 buckets',
      description: 'Delete empty or abandoned S3 buckets in dev environments',
      potentialSavings: 450,
      confidence: 'high',
    },
  ],
};

export const CostTrackingPage = () => {
  const config = useApi(configApiRef);
  
  const { value: costData, loading, error } = useAsync(async () => {
    // TODO: Replace with actual API call
    await new Promise(resolve => setTimeout(resolve, 1000));
    return mockCostData;
  }, []);

  const renderPieChart = (data: Array<{[key: string]: any}>, dataKey: string, nameKey: string) => (
    <ResponsiveContainer width="100%" height={300}>
      <PieChart>
        <Pie
          data={data}
          cx="50%"
          cy="50%"
          labelLine={false}
          label={({ name, percentage }) => `${name}: ${percentage}%`}
          outerRadius={80}
          fill="#8884d8"
          dataKey={dataKey}
        >
          {data.map((entry, index) => (
            <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
          ))}
        </Pie>
        <RechartsTooltip />
      </PieChart>
    </ResponsiveContainer>
  );

  const getBudgetStatus = (budget: any) => {
    const utilization = (budget.spent / budget.limit) * 100;
    if (utilization >= budget.alertThreshold) {
      return { color: 'error', icon: <WarningIcon />, text: 'At Risk' };
    } else if (utilization >= 50) {
      return { color: 'warning', icon: <InfoIcon />, text: 'On Track' };
    }
    return { color: 'success', icon: <CheckCircleIcon />, text: 'Healthy' };
  };

  const getRecommendationIcon = (type: string) => {
    switch (type) {
      case 'rightsizing':
        return <TrendingDownIcon />;
      case 'optimization':
        return <TrendingUpIcon />;
      case 'termination':
        return <WarningIcon />;
      default:
        return <InfoIcon />;
    }
  };

  if (loading) return <Progress />;
  if (error) return <Alert severity="error">Failed to load cost data: {error.message}</Alert>;
  if (!costData) return <Alert severity="warning">No cost data available</Alert>;

  const totalSavingsOpportunity = costData.recommendations.reduce(
    (sum, rec) => sum + rec.potentialSavings,
    0
  );

  return (
    <Page themeId="tool">
      <Header
        title="Cost Tracking & FinOps"
        subtitle="Monitor infrastructure costs and optimize spending across environments"
      />
      <Content>
        <ContentHeader title="Cost Analysis Dashboard">
          <SupportButton>
            Monitor and optimize your infrastructure costs with real-time insights,
            budget tracking, and automated recommendations for cost savings.
          </SupportButton>
        </ContentHeader>

        {/* Cost Overview Cards */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <MoneyIcon color="primary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      ${costData.totalCost.toLocaleString()}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Monthly Spend
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <TrendingDownIcon color="secondary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div" color="secondary">
                      ${totalSavingsOpportunity.toLocaleString()}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Savings Opportunity
                    </Typography>
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Budget Status
                </Typography>
                {costData.budgets.map((budget) => {
                  const status = getBudgetStatus(budget);
                  const utilization = (budget.spent / budget.limit) * 100;
                  return (
                    <Box key={budget.name} mb={1}>
                      <Box display="flex" alignItems="center" mb={0.5}>
                        <Chip
                          icon={status.icon}
                          label={status.text}
                          color={status.color as any}
                          size="small"
                        />
                        <Typography variant="body2" style={{ marginLeft: 8 }}>
                          {utilization.toFixed(1)}%
                        </Typography>
                      </Box>
                      <Typography variant="caption" color="textSecondary">
                        ${budget.spent.toLocaleString()} / ${budget.limit.toLocaleString()}
                      </Typography>
                    </Box>
                  );
                })}
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Active Alerts
                </Typography>
                <Alert severity="warning" variant="outlined">
                  Budget threshold exceeded
                </Alert>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Cost Trend Chart */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Cost Trend (6 Months)
                </Typography>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={costData.trend}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis 
                      dataKey="date" 
                      tick={{ fontSize: 12 }}
                      axisLine={{ stroke: '#666' }}
                    />
                    <YAxis 
                      tick={{ fontSize: 12 }}
                      axisLine={{ stroke: '#666' }}
                      tickFormatter={(value) => `$${value.toLocaleString()}`}
                    />
                    <RechartsTooltip 
                      formatter={(value: number) => [`$${value.toLocaleString()}`, 'Cost']}
                      labelStyle={{ color: '#666' }}
                    />
                    <Legend />
                    <Line
                      type="monotone"
                      dataKey="cost"
                      stroke="#0088FE"
                      strokeWidth={3}
                      dot={{ r: 6 }}
                      name="Actual Cost"
                    />
                    <Line
                      type="monotone"
                      dataKey="forecast"
                      stroke="#FF8042"
                      strokeDasharray="5 5"
                      strokeWidth={2}
                      dot={{ r: 4 }}
                      name="Forecast"
                    />
                  </LineChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Cost Breakdown Charts */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12} md={4}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Cost by Service
                </Typography>
                {renderPieChart(costData.breakdown.byService, 'cost', 'service')}
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={4}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Cost by Environment
                </Typography>
                {renderPieChart(costData.breakdown.byEnvironment, 'cost', 'environment')}
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={4}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Cost by Project
                </Typography>
                {renderPieChart(costData.breakdown.byProject, 'cost', 'project')}
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Optimization Recommendations */}
        <Grid container spacing={3}>
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Cost Optimization Recommendations
                </Typography>
                <Typography variant="body2" color="textSecondary" paragraph>
                  Potential monthly savings: ${totalSavingsOpportunity.toLocaleString()}
                </Typography>
                <List>
                  {costData.recommendations.map((rec, index) => (
                    <ListItem key={index} divider>
                      <ListItemIcon>
                        <Tooltip title={rec.type}>
                          {getRecommendationIcon(rec.type)}
                        </Tooltip>
                      </ListItemIcon>
                      <ListItemText
                        primary={
                          <Box display="flex" alignItems="center">
                            <Typography variant="subtitle2" style={{ flexGrow: 1 }}>
                              {rec.resource}
                            </Typography>
                            <Chip
                              label={`${rec.confidence} confidence`}
                              size="small"
                              color={rec.confidence === 'high' ? 'primary' : 'default'}
                            />
                            <Typography 
                              variant="subtitle2" 
                              color="secondary" 
                              style={{ marginLeft: 16 }}
                            >
                              Save ${rec.potentialSavings.toLocaleString()}/mo
                            </Typography>
                          </Box>
                        }
                        secondary={rec.description}
                      />
                    </ListItem>
                  ))}
                </List>
              </CardContent>
            </Card>
          </Grid>
        </Grid>
      </Content>
    </Page>
  );
};