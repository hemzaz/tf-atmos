import React, { useState } from 'react';
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
  LinearProgress,
  Tabs,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  IconButton,
} from '@material-ui/core';
import {
  Security as SecurityIcon,
  Warning as WarningIcon,
  CheckCircle as CheckCircleIcon,
  Error as ErrorIcon,
  Info as InfoIcon,
  Assignment as AssignmentIcon,
  AccountBalance as ComplianceIcon,
  TrendingUp as TrendingUpIcon,
  Visibility as VisibilityIcon,
} from '@material-ui/icons';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip as RechartsTooltip,
  ResponsiveContainer,
  PieChart,
  Pie,
  Cell,
  BarChart,
  Bar,
} from 'recharts';
import {
  Header,
  Page,
  Content,
  ContentHeader,
  SupportButton,
  Progress,
  StatusOK,
  StatusError,
  StatusWarning,
} from '@backstage/core-components';
import { useApi, configApiRef } from '@backstage/core-plugin-api';
import { useAsync } from 'react-use';
import { SecurityPosture, ComplianceRule, PolicyViolation } from '../types';

interface TabPanelProps {
  children?: React.ReactNode;
  index: number;
  value: number;
}

const TabPanel = (props: TabPanelProps) => {
  const { children, value, index, ...other } = props;
  return (
    <div
      role="tabpanel"
      hidden={value !== index}
      id={`compliance-tabpanel-${index}`}
      aria-labelledby={`compliance-tab-${index}`}
      {...other}
    >
      {value === index && <Box p={3}>{children}</Box>}
    </div>
  );
};

const COLORS = ['#0088FE', '#00C49F', '#FFBB28', '#FF8042'];

const mockSecurityPosture: SecurityPosture = {
  overallScore: 847,
  maxScore: 1000,
  lastAssessment: '2024-08-16T10:30:00Z',
  trends: [
    { date: '2024-01', score: 820 },
    { date: '2024-02', score: 835 },
    { date: '2024-03', score: 828 },
    { date: '2024-04', score: 842 },
    { date: '2024-05', score: 847 },
  ],
  frameworks: [
    {
      name: 'SOC2 Type II',
      score: 92,
      maxScore: 100,
      status: 'compliant',
      requirements: { total: 127, compliant: 117, nonCompliant: 8, notApplicable: 2 },
    },
    {
      name: 'ISO 27001',
      score: 85,
      maxScore: 100,
      status: 'partial',
      requirements: { total: 114, compliant: 97, nonCompliant: 15, notApplicable: 2 },
    },
    {
      name: 'CIS Controls',
      score: 78,
      maxScore: 100,
      status: 'partial',
      requirements: { total: 171, compliant: 133, nonCompliant: 32, notApplicable: 6 },
    },
  ],
  categories: [
    { category: 'Access Control', score: 95, maxScore: 100, rulesTotal: 45, rulesCompliant: 43 },
    { category: 'Encryption', score: 88, maxScore: 100, rulesTotal: 32, rulesCompliant: 28 },
    { category: 'Monitoring', score: 82, maxScore: 100, rulesTotal: 28, rulesCompliant: 23 },
    { category: 'Network Security', score: 91, maxScore: 100, rulesTotal: 38, rulesCompliant: 35 },
    { category: 'Data Protection', score: 75, maxScore: 100, rulesTotal: 25, rulesCompliant: 19 },
  ],
  criticalViolations: 2,
  highViolations: 8,
  mediumViolations: 23,
  lowViolations: 45,
};

const mockViolations: PolicyViolation[] = [
  {
    id: 'viol-001',
    ruleId: 'AWS-S3-001',
    resource: 'production-data-bucket',
    resourceType: 'S3 Bucket',
    environment: 'Production',
    description: 'S3 bucket allows public read access',
    severity: 'critical',
    detectedAt: '2024-08-15T14:30:00Z',
    status: 'open',
    assignee: 'security-team',
    dueDate: '2024-08-18T23:59:59Z',
    remediation: 'Remove public read permissions and implement proper bucket policies',
  },
  {
    id: 'viol-002',
    ruleId: 'AWS-EC2-002',
    resource: 'web-server-sg-prod',
    resourceType: 'Security Group',
    environment: 'Production',
    description: 'Security group allows SSH access from 0.0.0.0/0',
    severity: 'high',
    detectedAt: '2024-08-14T09:15:00Z',
    status: 'acknowledged',
    assignee: 'devops-team',
    remediation: 'Restrict SSH access to specific IP ranges or use bastion host',
  },
];

const getSeverityColor = (severity: string) => {
  switch (severity) {
    case 'critical': return 'error';
    case 'high': return 'warning';
    case 'medium': return 'info';
    case 'low': return 'default';
    default: return 'default';
  }
};

const getSeverityIcon = (severity: string) => {
  switch (severity) {
    case 'critical': return <ErrorIcon />;
    case 'high': return <WarningIcon />;
    case 'medium': return <InfoIcon />;
    case 'low': return <CheckCircleIcon />;
    default: return <InfoIcon />;
  }
};

const getStatusIcon = (status: string) => {
  switch (status) {
    case 'compliant': return <StatusOK />;
    case 'non-compliant': return <StatusError />;
    case 'warning': return <StatusWarning />;
    default: return <InfoIcon />;
  }
};

export const CompliancePage = () => {
  const config = useApi(configApiRef);
  const [tabValue, setTabValue] = useState(0);
  
  const { value: postureData, loading, error } = useAsync(async () => {
    await new Promise(resolve => setTimeout(resolve, 1000));
    return { posture: mockSecurityPosture, violations: mockViolations };
  }, []);

  const handleTabChange = (event: React.ChangeEvent<{}>, newValue: number) => {
    setTabValue(newValue);
  };

  if (loading) return <Progress />;
  if (error) return <Alert severity="error">Failed to load compliance data: {error.message}</Alert>;
  if (!postureData) return <Alert severity="warning">No compliance data available</Alert>;

  const { posture, violations } = postureData;
  const overallPercentage = (posture.overallScore / posture.maxScore) * 100;

  const violationData = [
    { name: 'Critical', count: posture.criticalViolations, color: '#FF4444' },
    { name: 'High', count: posture.highViolations, color: '#FF8042' },
    { name: 'Medium', count: posture.mediumViolations, color: '#FFBB28' },
    { name: 'Low', count: posture.lowViolations, color: '#00C49F' },
  ];

  return (
    <Page themeId="tool">
      <Header
        title="Security & Compliance"
        subtitle="Monitor security posture and compliance across all environments"
      />
      <Content>
        <ContentHeader title="Compliance Dashboard">
          <SupportButton>
            Track your organization's security and compliance posture with automated
            policy checks, violation management, and framework assessments.
          </SupportButton>
        </ContentHeader>

        {/* Security Posture Overview */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <SecurityIcon color="primary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      {overallPercentage.toFixed(1)}%
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Security Score
                    </Typography>
                    <LinearProgress
                      variant="determinate"
                      value={overallPercentage}
                      style={{ marginTop: 8 }}
                    />
                  </Box>
                </Box>
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <ErrorIcon color="error" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div" color="error">
                      {posture.criticalViolations + posture.highViolations}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Critical & High Issues
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
                  Framework Status
                </Typography>
                {posture.frameworks.map((framework) => (
                  <Box key={framework.name} mb={1}>
                    <Box display="flex" alignItems="center" justifyContent="between">
                      <Typography variant="body2">{framework.name}</Typography>
                      <Chip
                        size="small"
                        label={framework.status}
                        color={framework.status === 'compliant' ? 'primary' : 'default'}
                        style={{ marginLeft: 8 }}
                      />
                    </Box>
                    <LinearProgress
                      variant="determinate"
                      value={framework.score}
                      style={{ marginTop: 4 }}
                    />
                  </Box>
                ))}
              </CardContent>
            </Card>
          </Grid>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Violations by Severity
                </Typography>
                <ResponsiveContainer width="100%" height={120}>
                  <PieChart>
                    <Pie
                      data={violationData}
                      cx="50%"
                      cy="50%"
                      outerRadius={40}
                      dataKey="count"
                    >
                      {violationData.map((entry, index) => (
                        <Cell key={`cell-${index}`} fill={entry.color} />
                      ))}
                    </Pie>
                    <RechartsTooltip />
                  </PieChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Security Trend */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12}>
            <Card>
              <CardContent>
                <Typography variant="h6" gutterBottom>
                  Security Posture Trend
                </Typography>
                <ResponsiveContainer width="100%" height={300}>
                  <LineChart data={posture.trends}>
                    <CartesianGrid strokeDasharray="3 3" />
                    <XAxis dataKey="date" />
                    <YAxis />
                    <RechartsTooltip />
                    <Line
                      type="monotone"
                      dataKey="score"
                      stroke="#0088FE"
                      strokeWidth={3}
                      dot={{ r: 6 }}
                    />
                  </LineChart>
                </ResponsiveContainer>
              </CardContent>
            </Card>
          </Grid>
        </Grid>

        {/* Detailed Views */}
        <Card>
          <CardContent>
            <Tabs
              value={tabValue}
              onChange={handleTabChange}
              indicatorColor="primary"
              textColor="primary"
              variant="scrollable"
              scrollButtons="auto"
            >
              <Tab label="Policy Violations" icon={<ErrorIcon />} />
              <Tab label="Framework Compliance" icon={<ComplianceIcon />} />
              <Tab label="Category Breakdown" icon={<AssignmentIcon />} />
            </Tabs>

            <TabPanel value={tabValue} index={0}>
              <Typography variant="h6" gutterBottom>
                Active Policy Violations
              </Typography>
              <TableContainer component={Paper} variant="outlined">
                <Table size="small">
                  <TableHead>
                    <TableRow>
                      <TableCell>Resource</TableCell>
                      <TableCell>Type</TableCell>
                      <TableCell>Environment</TableCell>
                      <TableCell>Severity</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell>Detected</TableCell>
                      <TableCell>Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {violations.map((violation) => (
                      <TableRow key={violation.id}>
                        <TableCell>
                          <Typography variant="body2" style={{ fontWeight: 'bold' }}>
                            {violation.resource}
                          </Typography>
                          <Typography variant="caption" color="textSecondary">
                            {violation.description}
                          </Typography>
                        </TableCell>
                        <TableCell>{violation.resourceType}</TableCell>
                        <TableCell>{violation.environment}</TableCell>
                        <TableCell>
                          <Chip
                            icon={getSeverityIcon(violation.severity)}
                            label={violation.severity}
                            color={getSeverityColor(violation.severity) as any}
                            size="small"
                          />
                        </TableCell>
                        <TableCell>
                          <Chip
                            label={violation.status}
                            size="small"
                            variant="outlined"
                          />
                        </TableCell>
                        <TableCell>
                          {new Date(violation.detectedAt).toLocaleDateString()}
                        </TableCell>
                        <TableCell>
                          <Tooltip title="View Details">
                            <IconButton size="small">
                              <VisibilityIcon />
                            </IconButton>
                          </Tooltip>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </TabPanel>

            <TabPanel value={tabValue} index={1}>
              <Typography variant="h6" gutterBottom>
                Compliance Framework Status
              </Typography>
              <Grid container spacing={3}>
                {posture.frameworks.map((framework) => (
                  <Grid item xs={12} md={4} key={framework.name}>
                    <Card variant="outlined">
                      <CardContent>
                        <Box display="flex" alignItems="center" mb={2}>
                          <ComplianceIcon color="primary" />
                          <Typography variant="h6" style={{ marginLeft: 8 }}>
                            {framework.name}
                          </Typography>
                        </Box>
                        <Typography variant="h3" component="div" gutterBottom>
                          {framework.score}%
                        </Typography>
                        <LinearProgress
                          variant="determinate"
                          value={framework.score}
                          style={{ marginBottom: 16 }}
                        />
                        <Grid container spacing={2}>
                          <Grid item xs={6}>
                            <Typography variant="caption" color="textSecondary">
                              Compliant
                            </Typography>
                            <Typography variant="h6" color="primary">
                              {framework.requirements.compliant}
                            </Typography>
                          </Grid>
                          <Grid item xs={6}>
                            <Typography variant="caption" color="textSecondary">
                              Non-Compliant
                            </Typography>
                            <Typography variant="h6" color="error">
                              {framework.requirements.nonCompliant}
                            </Typography>
                          </Grid>
                        </Grid>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>
            </TabPanel>

            <TabPanel value={tabValue} index={2}>
              <Typography variant="h6" gutterBottom>
                Compliance by Category
              </Typography>
              <ResponsiveContainer width="100%" height={400}>
                <BarChart data={posture.categories}>
                  <CartesianGrid strokeDasharray="3 3" />
                  <XAxis 
                    dataKey="category" 
                    angle={-45}
                    textAnchor="end"
                    height={100}
                  />
                  <YAxis />
                  <RechartsTooltip />
                  <Bar dataKey="score" fill="#0088FE" />
                </BarChart>
              </ResponsiveContainer>
            </TabPanel>
          </CardContent>
        </Card>
      </Content>
    </Page>
  );
};