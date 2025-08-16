import {
  createPlugin,
  createRouteRef,
} from '@backstage/core-plugin-api';

export const complianceRouteRef = createRouteRef({
  id: 'compliance',
});

export const compliancePlugin = createPlugin({
  id: 'compliance',
  routes: {
    root: complianceRouteRef,
  },
});