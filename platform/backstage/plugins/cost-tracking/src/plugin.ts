import {
  createPlugin,
  createRouteRef,
} from '@backstage/core-plugin-api';

export const costTrackingRouteRef = createRouteRef({
  id: 'cost-tracking',
});

export const costTrackingPlugin = createPlugin({
  id: 'cost-tracking',
  routes: {
    root: costTrackingRouteRef,
  },
});