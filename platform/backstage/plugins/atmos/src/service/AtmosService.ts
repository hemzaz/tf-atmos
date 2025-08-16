import { Logger } from 'winston';
import { Config } from '@backstage/config';
import { exec } from 'child_process';
import { promisify } from 'util';
import * as fs from 'fs/promises';
import * as path from 'path';
import * as yaml from 'yaml';
import { 
  AtmosStack, 
  AtmosComponent, 
  AtmosWorkflow, 
  WorkflowExecutionRequest,
  WorkflowExecutionResult,
  StackValidationResult,
  ComponentValidationResult,
  AtmosConfig
} from '../types';

const execAsync = promisify(exec);

export interface AtmosServiceOptions {
  logger: Logger;
  config: Config;
}

export class AtmosService {
  private logger: Logger;
  private config: Config;
  private atmosConfigPath: string;
  private workingDirectory: string;

  constructor(options: AtmosServiceOptions) {
    this.logger = options.logger.child({ service: 'AtmosService' });
    this.config = options.config;
    
    // Get configuration from Backstage config
    this.atmosConfigPath = this.config.getOptionalString('platform.atmos.configPath') || '/app/atmos/atmos.yaml';
    this.workingDirectory = this.config.getOptionalString('platform.atmos.workingDirectory') || '/app';
    
    this.logger.info('AtmosService initialized', {
      configPath: this.atmosConfigPath,
      workingDirectory: this.workingDirectory,
    });
  }

  /**
   * Get all available Atmos stacks
   */
  async getStacks(): Promise<AtmosStack[]> {
    try {
      this.logger.debug('Getting Atmos stacks');
      
      const { stdout } = await this.execAtmosCommand('describe stacks --format=json');
      const stacksData = JSON.parse(stdout);
      
      const stacks: AtmosStack[] = Object.entries(stacksData).map(([stackName, stackData]: [string, any]) => ({
        name: stackName,
        tenant: this.extractFromStackName(stackName, 'tenant'),
        account: this.extractFromStackName(stackName, 'account'),
        environment: this.extractFromStackName(stackName, 'environment'),
        region: this.extractFromStackName(stackName, 'region'),
        components: Object.keys(stackData.components?.terraform || {}),
        variables: stackData.vars || {},
        metadata: stackData.metadata || {},
      }));
      
      this.logger.debug(`Found ${stacks.length} stacks`);
      return stacks;
    } catch (error) {
      this.logger.error('Failed to get Atmos stacks', { error: error.message });
      throw error;
    }
  }

  /**
   * Get all available Atmos components
   */
  async getComponents(): Promise<AtmosComponent[]> {
    try {
      this.logger.debug('Getting Atmos components');
      
      const { stdout } = await this.execAtmosCommand('list components --format=json');
      const componentsData = JSON.parse(stdout);
      
      const components: AtmosComponent[] = componentsData.map((comp: any) => ({
        name: comp.name,
        type: comp.type || 'terraform',
        path: comp.path,
        description: comp.description || '',
        variables: comp.variables || {},
        outputs: comp.outputs || {},
        metadata: comp.metadata || {},
      }));
      
      this.logger.debug(`Found ${components.length} components`);
      return components;
    } catch (error) {
      this.logger.error('Failed to get Atmos components', { error: error.message });
      throw error;
    }
  }

  /**
   * Get all available Atmos workflows
   */
  async getWorkflows(): Promise<AtmosWorkflow[]> {
    try {
      this.logger.debug('Getting Atmos workflows');
      
      // Read workflow files from filesystem
      const workflowsPath = path.join(this.workingDirectory, 'infrastructure/workflows');
      const workflowFiles = await fs.readdir(workflowsPath);
      
      const workflows: AtmosWorkflow[] = [];
      
      for (const file of workflowFiles.filter(f => f.endsWith('.yaml') || f.endsWith('.yml'))) {
        const filePath = path.join(workflowsPath, file);
        const content = await fs.readFile(filePath, 'utf8');
        const workflowData = yaml.parse(content);
        
        Object.entries(workflowData.workflows || {}).forEach(([name, workflow]: [string, any]) => {
          workflows.push({
            name,
            description: workflow.description || '',
            steps: workflow.steps || [],
            file: file,
            metadata: workflow.metadata || {},
          });
        });
      }
      
      this.logger.debug(`Found ${workflows.length} workflows`);
      return workflows;
    } catch (error) {
      this.logger.error('Failed to get Atmos workflows', { error: error.message });
      throw error;
    }
  }

  /**
   * Execute an Atmos workflow
   */
  async executeWorkflow(request: WorkflowExecutionRequest): Promise<WorkflowExecutionResult> {
    try {
      this.logger.info('Executing Atmos workflow', { 
        workflow: request.workflow,
        stack: request.stack,
        dryRun: request.dryRun 
      });

      const startTime = Date.now();
      let command = `workflow ${request.workflow}`;
      
      // Add parameters
      if (request.parameters) {
        const params = Object.entries(request.parameters)
          .map(([key, value]) => `${key}=${value}`)
          .join(' ');
        command += ` ${params}`;
      }
      
      // Add dry-run flag if requested
      if (request.dryRun) {
        command += ' --dry-run';
      }

      const { stdout, stderr } = await this.execAtmosCommand(command, {
        timeout: request.timeout || 1800000, // 30 minutes default
      });

      const executionTime = Date.now() - startTime;
      
      const result: WorkflowExecutionResult = {
        workflow: request.workflow,
        status: 'success',
        output: stdout,
        error: stderr || undefined,
        executionTime,
        timestamp: new Date().toISOString(),
      };

      this.logger.info('Workflow execution completed', { 
        workflow: request.workflow,
        executionTime: `${executionTime}ms`
      });

      return result;
    } catch (error) {
      this.logger.error('Workflow execution failed', { 
        workflow: request.workflow,
        error: error.message 
      });

      return {
        workflow: request.workflow,
        status: 'error',
        output: '',
        error: error.message,
        executionTime: Date.now() - Date.now(),
        timestamp: new Date().toISOString(),
      };
    }
  }

  /**
   * Validate a stack configuration
   */
  async validateStack(stackName: string): Promise<StackValidationResult> {
    try {
      this.logger.debug('Validating Atmos stack', { stack: stackName });
      
      const { stdout, stderr } = await this.execAtmosCommand(`validate stacks -s ${stackName}`);
      
      return {
        stack: stackName,
        valid: true,
        errors: [],
        warnings: this.parseWarningsFromOutput(stderr),
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      this.logger.warn('Stack validation failed', { 
        stack: stackName, 
        error: error.message 
      });

      return {
        stack: stackName,
        valid: false,
        errors: [error.message],
        warnings: [],
        timestamp: new Date().toISOString(),
      };
    }
  }

  /**
   * Validate a component
   */
  async validateComponent(componentName: string, stackName?: string): Promise<ComponentValidationResult> {
    try {
      this.logger.debug('Validating Atmos component', { 
        component: componentName,
        stack: stackName 
      });
      
      let command = `terraform validate ${componentName}`;
      if (stackName) {
        command += ` -s ${stackName}`;
      }

      const { stdout, stderr } = await this.execAtmosCommand(command);
      
      return {
        component: componentName,
        stack: stackName,
        valid: true,
        errors: [],
        warnings: this.parseWarningsFromOutput(stderr),
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      this.logger.warn('Component validation failed', { 
        component: componentName,
        stack: stackName,
        error: error.message 
      });

      return {
        component: componentName,
        stack: stackName,
        valid: false,
        errors: [error.message],
        warnings: [],
        timestamp: new Date().toISOString(),
      };
    }
  }

  /**
   * Get Atmos configuration
   */
  async getConfig(): Promise<AtmosConfig> {
    try {
      const configContent = await fs.readFile(this.atmosConfigPath, 'utf8');
      const config = yaml.parse(configContent);
      
      return {
        version: config.version || '1.0',
        components: config.components || {},
        stacks: config.stacks || {},
        workflows: config.workflows || {},
        integrations: config.integrations || {},
      };
    } catch (error) {
      this.logger.error('Failed to read Atmos configuration', { error: error.message });
      throw error;
    }
  }

  /**
   * Execute an Atmos command
   */
  private async execAtmosCommand(command: string, options: { timeout?: number } = {}): Promise<{ stdout: string; stderr: string }> {
    const fullCommand = `atmos ${command}`;
    const execOptions = {
      cwd: this.workingDirectory,
      timeout: options.timeout || 30000,
      env: {
        ...process.env,
        ATMOS_CLI_CONFIG_PATH: this.atmosConfigPath,
      },
    };

    this.logger.debug('Executing Atmos command', { 
      command: fullCommand,
      cwd: execOptions.cwd 
    });

    try {
      const result = await execAsync(fullCommand, execOptions);
      return result;
    } catch (error) {
      this.logger.error('Atmos command failed', { 
        command: fullCommand,
        error: error.message,
        stderr: error.stderr 
      });
      throw error;
    }
  }

  /**
   * Extract tenant/account/environment from stack name
   */
  private extractFromStackName(stackName: string, part: 'tenant' | 'account' | 'environment' | 'region'): string {
    // Assuming format: orgs/{tenant}/{account}/{region}/{environment}
    // or simplified: {tenant}-{account}-{environment}
    
    if (stackName.includes('/')) {
      const parts = stackName.split('/');
      switch (part) {
        case 'tenant': return parts[1] || '';
        case 'account': return parts[2] || '';
        case 'region': return parts[3] || '';
        case 'environment': return parts[4] || '';
        default: return '';
      }
    } else if (stackName.includes('-')) {
      const parts = stackName.split('-');
      switch (part) {
        case 'tenant': return parts[0] || '';
        case 'account': return parts[1] || '';
        case 'environment': return parts[2] || '';
        case 'region': return parts[3] || '';
        default: return '';
      }
    }
    
    return '';
  }

  /**
   * Parse warnings from command output
   */
  private parseWarningsFromOutput(output: string): string[] {
    const warnings: string[] = [];
    const lines = output.split('\n');
    
    for (const line of lines) {
      if (line.includes('Warning:') || line.includes('WARN')) {
        warnings.push(line.trim());
      }
    }
    
    return warnings;
  }
}