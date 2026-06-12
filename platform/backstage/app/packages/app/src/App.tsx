import { createApp } from '@backstage/frontend-defaults';
import { createFrontendModule } from '@backstage/frontend-plugin-api';
import { githubAuthApiRef } from '@backstage/core-plugin-api';
import { SignInPageBlueprint } from '@backstage/plugin-app-react';
import { SignInPage } from '@backstage/core-components';

import catalogPlugin from '@backstage/plugin-catalog/alpha';
import catalogGraphPlugin from '@backstage/plugin-catalog-graph/alpha';
import kubernetesPlugin from '@backstage/plugin-kubernetes/alpha';
import scaffolderPlugin from '@backstage/plugin-scaffolder/alpha';
import searchPlugin from '@backstage/plugin-search/alpha';
import techdocsPlugin from '@backstage/plugin-techdocs/alpha';
import apiDocsPlugin from '@backstage/plugin-api-docs/alpha';
import orgPlugin from '@backstage/plugin-org/alpha';
import userSettingsPlugin from '@backstage/plugin-user-settings/alpha';
import notificationsPlugin from '@backstage/plugin-notifications/alpha';
import signalsPlugin from '@backstage/plugin-signals/alpha';

import { navModule } from './modules/nav';

const signInPage = SignInPageBlueprint.make({
  params: {
    loader: async () => props =>
      (
        <SignInPage
          {...props}
          providers={[
            {
              id: 'github-auth-provider',
              title: 'GitHub',
              message: 'Sign in using GitHub',
              apiRef: githubAuthApiRef,
            },
            'guest',
          ]}
        />
      ),
  },
});

export default createApp({
  features: [
    catalogPlugin,
    catalogGraphPlugin,
    kubernetesPlugin,
    scaffolderPlugin,
    searchPlugin,
    techdocsPlugin,
    apiDocsPlugin,
    orgPlugin,
    userSettingsPlugin,
    notificationsPlugin,
    signalsPlugin,
    navModule,
    createFrontendModule({
      pluginId: 'app',
      extensions: [signInPage],
    }),
  ],
});
