/*
 * Hi!
 *
 * Note that this is an EXAMPLE Backstage backend. Please check the README.
 *
 * Happy hacking!
 */

import { createBackend } from '@backstage/backend-defaults';
import { createBackendModule } from '@backstage/backend-plugin-api';
import { loggerToWinstonLogger } from '@backstage/backend-common';

// Custom platform plugins
import { atmosPlugin } from '@internal/backstage-plugin-atmos';
import { costTrackingPlugin } from '@internal/backstage-plugin-cost-tracking';
import { compliancePlugin } from '@internal/backstage-plugin-compliance';

const backend = createBackend();

// Core Backstage plugins
backend.add(import('@backstage/plugin-app-backend/alpha'));
backend.add(import('@backstage/plugin-proxy-backend/alpha'));
backend.add(import('@backstage/plugin-scaffolder-backend/alpha'));
backend.add(import('@backstage/plugin-techdocs-backend/alpha'));

// auth plugin
backend.add(import('@backstage/plugin-auth-backend'));
backend.add(
  import('@backstage/plugin-auth-backend-module-github-provider'),
);
// See https://backstage.io/docs/auth/guest for how to set up guest access
backend.add(import('@backstage/plugin-auth-backend-module-guest-provider'));
// See https://backstage.io/docs/auth/aws for how to set up AWS IAM authentication
backend.add(import('@backstage/plugin-auth-backend-module-aws-iam-provider'));

// catalog plugin
backend.add(import('@backstage/plugin-catalog-backend/alpha'));
backend.add(
  import('@backstage/plugin-catalog-backend-module-scaffolder-entity-model'),
);
backend.add(import('@backstage/plugin-catalog-backend-module-github/alpha'));

// permission plugin
backend.add(import('@backstage/plugin-permission-backend/alpha'));
backend.add(
  import(
    '@backstage/plugin-permission-backend-module-allow-all-policy'
  ),
);

// search plugin
backend.add(import('@backstage/plugin-search-backend/alpha'));
backend.add(import('@backstage/plugin-search-backend-module-pg/alpha'));
backend.add(import('@backstage/plugin-search-backend-module-catalog/alpha'));
backend.add(import('@backstage/plugin-search-backend-module-techdocs/alpha'));

// kubernetes plugin
backend.add(import('@backstage/plugin-kubernetes-backend/alpha'));

// Custom platform plugins
backend.add(
  createBackendModule({
    pluginId: 'atmos',
    moduleId: 'platform-integration',
    register(reg) {
      reg.registerInit({
        deps: {
          logger: 'core.logger',
          config: 'core.config',
          httpRouter: 'core.httpRouter',
        },
        async init({ logger, config, httpRouter }) {
          const winstonLogger = loggerToWinstonLogger(logger);
          
          // Initialize Atmos plugin
          const atmosRouter = await atmosPlugin({
            logger: winstonLogger,
            config,
          });
          
          // Initialize cost tracking plugin
          const costRouter = await costTrackingPlugin({
            logger: winstonLogger,
            config,
          });
          
          // Initialize compliance plugin  
          const complianceRouter = await compliancePlugin({
            logger: winstonLogger,
            config,
          });
          
          // Mount plugin routes
          httpRouter.use('/api/platform/atmos', atmosRouter);
          httpRouter.use('/api/platform/cost', costRouter);
          httpRouter.use('/api/platform/compliance', complianceRouter);
          
          logger.info('Platform integration modules initialized');
        },
      });
    },
  }),
);

// Health check endpoint
backend.add(
  createBackendModule({
    pluginId: 'health',
    moduleId: 'platform-health',
    register(reg) {
      reg.registerInit({
        deps: {
          httpRouter: 'core.httpRouter',
          logger: 'core.logger',
        },
        async init({ httpRouter, logger }) {
          httpRouter.get('/health', (_req, res) => {
            res.json({
              status: 'ok',
              timestamp: new Date().toISOString(),
              version: process.env.npm_package_version || '0.0.0',
              uptime: process.uptime(),
              platform: {
                atmos: 'available',
                terraform: 'available',
                kubernetes: 'available',
              },
            });
          });
          
          logger.info('Health check endpoint registered');
        },
      });
    },
  }),
);

backend.start();