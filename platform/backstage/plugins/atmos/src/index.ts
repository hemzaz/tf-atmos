// Frontend exports
import { createPlugin, createRouteRef } from '@backstage/core-plugin-api';

export const atmosRouteRef = createRouteRef({
  id: 'atmos',
});

export const atmospherePlugin = createPlugin({
  id: 'atmos',
  routes: {
    root: atmosRouteRef,
  },
});

// Frontend components
export { AtmosPage } from './components/AtmosPage';

// Backend exports
import { createBackendPlugin } from '@backstage/backend-plugin-api';
import { Router } from 'express';
import { Logger } from 'winston';
import { Config } from '@backstage/config';
import { AtmosService } from './service/AtmosService';
import { createRouter } from './router';

export interface AtmosPluginOptions {
  logger: Logger;
  config: Config;
}

export const atmosPlugin = async (options: AtmosPluginOptions): Promise<Router> => {
  const { logger, config } = options;
  
  logger.info('Initializing Atmos plugin');
  
  const atmosService = new AtmosService({
    logger,
    config,
  });
  
  return await createRouter({
    logger,
    config,
    atmosService,
  });
};

export const atmosBackendPlugin = createBackendPlugin({
  pluginId: 'atmos',
  register(env) {
    env.registerInit({
      deps: {
        httpRouter: 'core.httpRouter',
        logger: 'core.logger',
        config: 'core.config',
      },
      async init({ httpRouter, logger, config }) {
        const router = await atmosPlugin({ logger, config });
        httpRouter.use('/api/platform/atmos', router);
      },
    });
  },
});

export * from './service/AtmosService';
export * from './types';
export * from './router';