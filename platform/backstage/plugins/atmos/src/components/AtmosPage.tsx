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
  Tabs,
  Tab,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Button,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  CircularProgress,
  TextField,
  Select,
  MenuItem,
  FormControl,
  InputLabel,
} from '@material-ui/core';
import {
  Cloud as CloudIcon,
  PlayArrow as PlayIcon,
  Storage as StorageIcon,
  Security as SecurityIcon,
  Visibility as VisibilityIcon,
  Settings as SettingsIcon,
  CheckCircle as CheckCircleIcon,
  Error as ErrorIcon,
  Warning as WarningIcon,
  Info as InfoIcon,
} from '@material-ui/icons';
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
  StatusPending,
} from '@backstage/core-components';
import { useApi, configApiRef } from '@backstage/core-plugin-api';
import { useAsync } from 'react-use';

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
      id={`atmos-tabpanel-${index}`}
      aria-labelledby={`atmos-tab-${index}`}
      {...other}
    >
      {value === index && <Box p={3}>{children}</Box>}
    </div>
  );
};

interface AtmosStack {
  name: string;
  tenant: string;
  account: string;
  environment: string;
  region: string;
  status: 'healthy' | 'warning' | 'error' | 'unknown';
  components: string[];
  lastDeployed: string;
}

interface AtmosComponent {
  name: string;
  type: 'terraform' | 'helmfile';
  description: string;
  status: 'deployed' | 'pending' | 'failed' | 'not-deployed';
  version: string;
  stacks: string[];
  lastUpdated: string;
}

interface WorkflowExecution {
  id: string;
  workflow: string;
  stack: string;
  status: 'running' | 'completed' | 'failed' | 'pending';
  startedAt: string;
  completedAt?: string;
  logs?: string[];
}

const mockStacks: AtmosStack[] = [
  {
    name: 'fnx-dev-testenv-01',
    tenant: 'fnx',
    account: 'dev',
    environment: 'testenv-01',
    region: 'us-west-2',
    status: 'healthy',
    components: ['vpc', 'eks', 'rds', 'lambda'],
    lastDeployed: '2024-08-15T14:30:00Z',
  },
  {
    name: 'fnx-prod-us-west-2',
    tenant: 'fnx',
    account: 'prod',
    environment: 'us-west-2',
    region: 'us-west-2',
    status: 'warning',
    components: ['vpc', 'eks', 'rds', 'lambda', 'secretsmanager'],
    lastDeployed: '2024-08-14T09:15:00Z',
  },
];

const mockComponents: AtmosComponent[] = [
  {
    name: 'vpc',
    type: 'terraform',
    description: 'Virtual Private Cloud with public/private subnets',
    status: 'deployed',
    version: '1.2.3',
    stacks: ['fnx-dev-testenv-01', 'fnx-prod-us-west-2'],
    lastUpdated: '2024-08-15T14:30:00Z',
  },
  {
    name: 'eks',
    type: 'terraform',
    description: 'Kubernetes cluster with managed node groups',
    status: 'deployed',
    version: '2.1.0',
    stacks: ['fnx-dev-testenv-01', 'fnx-prod-us-west-2'],
    lastUpdated: '2024-08-15T12:00:00Z',
  },
  {
    name: 'rds',
    type: 'terraform',
    description: 'PostgreSQL database with encryption and backups',
    status: 'pending',
    version: '1.5.2',
    stacks: ['fnx-dev-testenv-01'],
    lastUpdated: '2024-08-15T10:45:00Z',
  },
];

const getStatusIcon = (status: string) => {
  switch (status) {
    case 'healthy':
    case 'deployed':
    case 'completed':
      return <StatusOK />;
    case 'warning':
    case 'pending':
    case 'running':
      return <StatusPending />;
    case 'error':
    case 'failed':
      return <StatusError />;
    default:
      return <InfoIcon />;
  }
};

const getStatusColor = (status: string) => {
  switch (status) {
    case 'healthy':
    case 'deployed':
    case 'completed':
      return 'success';
    case 'warning':
    case 'pending':
    case 'running':
      return 'warning';
    case 'error':
    case 'failed':
      return 'error';
    default:
      return 'default';
  }
};

export const AtmosPage = () => {
  const config = useApi(configApiRef);
  const [tabValue, setTabValue] = useState(0);
  const [workflowDialog, setWorkflowDialog] = useState(false);
  const [selectedWorkflow, setSelectedWorkflow] = useState('');
  const [selectedStack, setSelectedStack] = useState('');
  const [workflowExecuting, setWorkflowExecuting] = useState(false);

  const { value: atmosData, loading, error } = useAsync(async () => {
    await new Promise(resolve => setTimeout(resolve, 1000));
    return {
      stacks: mockStacks,
      components: mockComponents,
      workflows: [
        'plan-environment',
        'apply-environment', 
        'validate',
        'lint',
        'drift-detection',
        'onboard-environment',
      ],
    };
  }, []);

  const handleTabChange = (event: React.ChangeEvent<{}>, newValue: number) => {
    setTabValue(newValue);
  };

  const handleWorkflowExecute = async () => {
    setWorkflowExecuting(true);
    try {
      // TODO: Replace with actual API call
      await new Promise(resolve => setTimeout(resolve, 2000));
      setWorkflowDialog(false);
      setSelectedWorkflow('');
      setSelectedStack('');
    } catch (err) {
      console.error('Workflow execution failed:', err);
    } finally {
      setWorkflowExecuting(false);
    }
  };

  if (loading) return <Progress />;
  if (error) return <Alert severity="error">Failed to load Atmos data: {error.message}</Alert>;
  if (!atmosData) return <Alert severity="warning">No Atmos data available</Alert>;

  const { stacks, components, workflows } = atmosData;

  return (
    <Page themeId="tool">
      <Header
        title="Atmos Infrastructure Management"
        subtitle="Manage Terraform components and execute workflows across all environments"
      />
      <Content>
        <ContentHeader title="Infrastructure Dashboard">
          <SupportButton>
            Manage your infrastructure as code with Atmos. Execute workflows,
            view component status, and manage deployments across all environments.
          </SupportButton>
        </ContentHeader>

        {/* Quick Actions */}
        <Grid container spacing={2} style={{ marginBottom: 24 }}>
          <Grid item>
            <Button
              variant="contained"
              color="primary"
              startIcon={<PlayIcon />}
              onClick={() => setWorkflowDialog(true)}
            >
              Execute Workflow
            </Button>
          </Grid>
          <Grid item>
            <Button variant="outlined" startIcon={<CheckCircleIcon />}>
              Validate All
            </Button>
          </Grid>
          <Grid item>
            <Button variant="outlined" startIcon={<WarningIcon />}>
              Drift Detection
            </Button>
          </Grid>
        </Grid>

        {/* Summary Cards */}
        <Grid container spacing={3} style={{ marginBottom: 24 }}>
          <Grid item xs={12} md={3}>
            <Card>
              <CardContent>
                <Box display="flex" alignItems="center">
                  <CloudIcon color="primary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      {stacks.length}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Active Stacks
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
                  <SettingsIcon color="primary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      {components.length}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Components
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
                  <CheckCircleIcon color="primary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      {components.filter(c => c.status === 'deployed').length}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Deployed
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
                  <WarningIcon color="secondary" />
                  <Box ml={2}>
                    <Typography variant="h4" component="div">
                      {stacks.filter(s => s.status === 'warning').length}
                    </Typography>
                    <Typography color="textSecondary" variant="body2">
                      Warnings
                    </Typography>
                  </Box>
                </Box>
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
              <Tab label="Stacks" icon={<CloudIcon />} />
              <Tab label="Components" icon={<SettingsIcon />} />
              <Tab label="Workflows" icon={<PlayIcon />} />
            </Tabs>

            <TabPanel value={tabValue} index={0}>
              <Typography variant="h6" gutterBottom>
                Infrastructure Stacks
              </Typography>
              <TableContainer component={Paper} variant="outlined">
                <Table>
                  <TableHead>
                    <TableRow>
                      <TableCell>Stack</TableCell>
                      <TableCell>Tenant</TableCell>
                      <TableCell>Environment</TableCell>
                      <TableCell>Region</TableCell>
                      <TableCell>Status</TableCell>
                      <TableCell>Components</TableCell>
                      <TableCell>Last Deployed</TableCell>
                      <TableCell>Actions</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {stacks.map((stack) => (
                      <TableRow key={stack.name}>
                        <TableCell>
                          <Typography variant="body2" style={{ fontWeight: 'bold' }}>
                            {stack.name}
                          </Typography>
                        </TableCell>
                        <TableCell>{stack.tenant}</TableCell>
                        <TableCell>{stack.environment}</TableCell>
                        <TableCell>{stack.region}</TableCell>
                        <TableCell>
                          <Box display="flex" alignItems="center">
                            {getStatusIcon(stack.status)}
                            <Chip
                              label={stack.status}
                              color={getStatusColor(stack.status) as any}
                              size="small"
                              style={{ marginLeft: 8 }}
                            />
                          </Box>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2">
                            {stack.components.join(', ')}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          {new Date(stack.lastDeployed).toLocaleDateString()}
                        </TableCell>
                        <TableCell>
                          <IconButton size="small">
                            <VisibilityIcon />
                          </IconButton>
                          <IconButton size="small">
                            <PlayIcon />
                          </IconButton>
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </TableContainer>
            </TabPanel>

            <TabPanel value={tabValue} index={1}>
              <Typography variant="h6" gutterBottom>
                Terraform Components
              </Typography>
              <Grid container spacing={3}>
                {components.map((component) => (
                  <Grid item xs={12} md={6} lg={4} key={component.name}>
                    <Card variant="outlined" style={{ height: '100%' }}>
                      <CardContent>
                        <Box display="flex" alignItems="center" mb={2}>
                          <StorageIcon color="primary" />
                          <Typography variant="h6" style={{ marginLeft: 8 }}>
                            {component.name}
                          </Typography>
                          <Box ml="auto">
                            {getStatusIcon(component.status)}
                          </Box>
                        </Box>
                        <Typography variant="body2" color="textSecondary" paragraph>
                          {component.description}
                        </Typography>
                        <Box display="flex" alignItems="center" mb={1}>
                          <Typography variant="caption" color="textSecondary">
                            Type: {component.type}
                          </Typography>
                          <Chip
                            label={`v${component.version}`}
                            size="small"
                            style={{ marginLeft: 'auto' }}
                          />
                        </Box>
                        <Box display="flex" alignItems="center">
                          <Chip
                            label={component.status}
                            color={getStatusColor(component.status) as any}
                            size="small"
                          />
                          <Typography variant="caption" color="textSecondary" style={{ marginLeft: 'auto' }}>
                            {component.stacks.length} stack{component.stacks.length !== 1 ? 's' : ''}
                          </Typography>
                        </Box>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>
            </TabPanel>

            <TabPanel value={tabValue} index={2}>
              <Typography variant="h6" gutterBottom>
                Available Workflows
              </Typography>
              <Grid container spacing={2}>
                {workflows.map((workflow) => (
                  <Grid item xs={12} md={6} lg={4} key={workflow}>
                    <Card variant="outlined">
                      <CardContent>
                        <Box display="flex" alignItems="center" justifyContent="space-between">
                          <Box>
                            <Typography variant="h6" gutterBottom>
                              {workflow}
                            </Typography>
                            <Typography variant="body2" color="textSecondary">
                              Execute {workflow.replace('-', ' ')} workflow
                            </Typography>
                          </Box>
                          <Button
                            variant="outlined"
                            size="small"
                            startIcon={<PlayIcon />}
                            onClick={() => {
                              setSelectedWorkflow(workflow);
                              setWorkflowDialog(true);
                            }}
                          >
                            Run
                          </Button>
                        </Box>
                      </CardContent>
                    </Card>
                  </Grid>
                ))}
              </Grid>
            </TabPanel>
          </CardContent>
        </Card>

        {/* Workflow Execution Dialog */}
        <Dialog 
          open={workflowDialog} 
          onClose={() => setWorkflowDialog(false)}
          maxWidth="sm"
          fullWidth
        >
          <DialogTitle>Execute Workflow</DialogTitle>
          <DialogContent>
            <Box mb={3}>
              <FormControl fullWidth margin="normal">
                <InputLabel>Workflow</InputLabel>
                <Select
                  value={selectedWorkflow}
                  onChange={(e) => setSelectedWorkflow(e.target.value as string)}
                  disabled={workflowExecuting}
                >
                  {workflows.map((workflow) => (
                    <MenuItem key={workflow} value={workflow}>
                      {workflow}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
              <FormControl fullWidth margin="normal">
                <InputLabel>Stack</InputLabel>
                <Select
                  value={selectedStack}
                  onChange={(e) => setSelectedStack(e.target.value as string)}
                  disabled={workflowExecuting}
                >
                  {stacks.map((stack) => (
                    <MenuItem key={stack.name} value={stack.name}>
                      {stack.name}
                    </MenuItem>
                  ))}
                </Select>
              </FormControl>
            </Box>
            {workflowExecuting && (
              <Box display="flex" alignItems="center" mt={2}>
                <CircularProgress size={20} />
                <Typography variant="body2" style={{ marginLeft: 8 }}>
                  Executing workflow...
                </Typography>
              </Box>
            )}
          </DialogContent>
          <DialogActions>
            <Button 
              onClick={() => setWorkflowDialog(false)} 
              disabled={workflowExecuting}
            >
              Cancel
            </Button>
            <Button
              onClick={handleWorkflowExecute}
              color="primary"
              variant="contained"
              disabled={!selectedWorkflow || !selectedStack || workflowExecuting}
              startIcon={workflowExecuting ? <CircularProgress size={16} /> : <PlayIcon />}
            >
              Execute
            </Button>
          </DialogActions>
        </Dialog>
      </Content>
    </Page>
  );
};