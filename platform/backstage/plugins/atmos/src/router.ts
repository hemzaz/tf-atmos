import { Router } from 'express';
import { Logger } from 'winston';
import { Config } from '@backstage/config';
import { AtmosService } from './service/AtmosService';
import { WorkflowExecutionRequest, ServiceRequest } from './types';
import { z } from 'zod';

export interface RouterOptions {
  logger: Logger;
  config: Config;
  atmosService: AtmosService;
}

// Validation schemas
const WorkflowExecutionRequestSchema = z.object({
  workflow: z.string(),
  stack: z.string().optional(),
  parameters: z.record(z.string()).optional(),
  dryRun: z.boolean().default(false),
  timeout: z.number().optional(),
});

const ServiceRequestSchema = z.object({
  serviceName: z.string(),
  template: z.string(),
  tenant: z.string(),
  account: z.string(),
  environment: z.string(),
  region: z.string().optional(),
  parameters: z.record(z.any()),
  metadata: z.record(z.any()).optional(),
});

export async function createRouter(options: RouterOptions): Promise<Router> {
  const { logger, config, atmosService } = options;
  const router = Router();

  // Middleware for request logging
  router.use((req, res, next) => {
    logger.info(`${req.method} ${req.path}`, {
      userAgent: req.headers['user-agent'],
      ip: req.ip,
    });
    next();
  });

  // Health check endpoint
  router.get('/health', (_req, res) => {
    res.json({
      status: 'ok',
      service: 'atmos-plugin',
      timestamp: new Date().toISOString(),
    });
  });

  // Get all stacks
  router.get('/stacks', async (_req, res) => {
    try {
      const stacks = await atmosService.getStacks();
      res.json(stacks);
    } catch (error) {
      logger.error('Failed to get stacks', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to get stacks', 
        message: error.message 
      });
    }
  });

  // Get specific stack
  router.get('/stacks/:stackName', async (req, res) => {
    try {
      const { stackName } = req.params;
      const stacks = await atmosService.getStacks();
      const stack = stacks.find(s => s.name === stackName);
      
      if (!stack) {
        return res.status(404).json({ 
          error: 'Stack not found', 
          stack: stackName 
        });
      }
      
      res.json(stack);
    } catch (error) {
      logger.error('Failed to get stack', { 
        stack: req.params.stackName,
        error: error.message 
      });
      res.status(500).json({ 
        error: 'Failed to get stack', 
        message: error.message 
      });
    }
  });

  // Validate stack
  router.post('/stacks/:stackName/validate', async (req, res) => {
    try {
      const { stackName } = req.params;
      const result = await atmosService.validateStack(stackName);
      res.json(result);
    } catch (error) {
      logger.error('Failed to validate stack', { 
        stack: req.params.stackName,
        error: error.message 
      });
      res.status(500).json({ 
        error: 'Failed to validate stack', 
        message: error.message 
      });
    }
  });

  // Get all components
  router.get('/components', async (_req, res) => {
    try {
      const components = await atmosService.getComponents();
      res.json(components);
    } catch (error) {
      logger.error('Failed to get components', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to get components', 
        message: error.message 
      });
    }
  });

  // Get specific component
  router.get('/components/:componentName', async (req, res) => {
    try {
      const { componentName } = req.params;
      const components = await atmosService.getComponents();
      const component = components.find(c => c.name === componentName);
      
      if (!component) {
        return res.status(404).json({ 
          error: 'Component not found', 
          component: componentName 
        });
      }
      
      res.json(component);
    } catch (error) {
      logger.error('Failed to get component', { 
        component: req.params.componentName,
        error: error.message 
      });
      res.status(500).json({ 
        error: 'Failed to get component', 
        message: error.message 
      });
    }
  });

  // Validate component
  router.post('/components/:componentName/validate', async (req, res) => {
    try {
      const { componentName } = req.params;
      const { stack } = req.body;
      const result = await atmosService.validateComponent(componentName, stack);
      res.json(result);
    } catch (error) {
      logger.error('Failed to validate component', { 
        component: req.params.componentName,
        error: error.message 
      });
      res.status(500).json({ 
        error: 'Failed to validate component', 
        message: error.message 
      });
    }
  });

  // Get all workflows
  router.get('/workflows', async (_req, res) => {
    try {
      const workflows = await atmosService.getWorkflows();
      res.json(workflows);
    } catch (error) {
      logger.error('Failed to get workflows', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to get workflows', 
        message: error.message 
      });
    }
  });

  // Execute workflow
  router.post('/workflows/execute', async (req, res) => {
    try {
      const validationResult = WorkflowExecutionRequestSchema.safeParse(req.body);
      
      if (!validationResult.success) {
        return res.status(400).json({
          error: 'Invalid request body',
          details: validationResult.error.errors,
        });
      }

      const request: WorkflowExecutionRequest = validationResult.data;
      const result = await atmosService.executeWorkflow(request);
      
      res.json(result);
    } catch (error) {
      logger.error('Failed to execute workflow', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to execute workflow', 
        message: error.message 
      });
    }
  });

  // Provision service (high-level operation)
  router.post('/services/provision', async (req, res) => {
    try {
      const validationResult = ServiceRequestSchema.safeParse(req.body);
      
      if (!validationResult.success) {
        return res.status(400).json({
          error: 'Invalid service request',
          details: validationResult.error.errors,
        });
      }

      const request: ServiceRequest = validationResult.data;
      
      // Convert service request to workflow execution
      const workflowRequest: WorkflowExecutionRequest = {
        workflow: 'onboard-environment',
        parameters: {
          tenant: request.tenant,
          account: request.account,
          environment: request.environment,
          region: request.region || 'us-west-2',
          ...request.parameters,
        },
        dryRun: false,
      };

      const result = await atmosService.executeWorkflow(workflowRequest);
      
      res.json({
        serviceName: request.serviceName,
        status: result.status === 'success' ? 'provisioning' : 'error',
        stack: `${request.tenant}-${request.account}-${request.environment}`,
        workflowResult: result,
        timestamp: new Date().toISOString(),
      });
      
    } catch (error) {
      logger.error('Failed to provision service', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to provision service', 
        message: error.message 
      });
    }
  });

  // Get Atmos configuration
  router.get('/config', async (_req, res) => {
    try {
      const config = await atmosService.getConfig();
      res.json(config);
    } catch (error) {
      logger.error('Failed to get Atmos config', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to get Atmos config', 
        message: error.message 
      });
    }
  });

  // Get platform metrics
  router.get('/metrics', async (_req, res) => {
    try {
      const [stacks, components, workflows] = await Promise.all([
        atmosService.getStacks(),
        atmosService.getComponents(),
        atmosService.getWorkflows(),
      ]);

      const metrics = {
        stacks: {
          total: stacks.length,
          healthy: stacks.length, // TODO: Implement health checks
          unhealthy: 0,
        },
        components: {
          total: components.length,
          deployed: components.length, // TODO: Implement deployment status
          failed: 0,
        },
        workflows: {
          total: workflows.length,
          successful: 0, // TODO: Implement execution tracking
          failed: 0,
          lastRun: new Date().toISOString(),
        },
        cost: {
          monthly: 0, // TODO: Implement cost tracking
          trending: 'stable' as const,
          currency: 'USD',
        },
        compliance: {
          score: 85, // TODO: Implement compliance scoring
          checks: 10,
          passed: 8,
          failed: 2,
        },
      };

      res.json(metrics);
    } catch (error) {
      logger.error('Failed to get platform metrics', { error: error.message });
      res.status(500).json({ 
        error: 'Failed to get platform metrics', 
        message: error.message 
      });
    }
  });

  // Error handling middleware
  router.use((error: Error, _req: any, res: any, _next: any) => {
    logger.error('Unhandled error in Atmos router', { error: error.message });
    res.status(500).json({
      error: 'Internal server error',
      message: error.message,
    });
  });

  logger.info('Atmos router initialized with all endpoints');
  
  return router;
}