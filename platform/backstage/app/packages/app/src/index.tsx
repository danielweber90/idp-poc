// crypto.randomUUID() requires HTTPS in browsers — polyfill for HTTP dev/PoC deployments
if (typeof globalThis.crypto?.randomUUID !== 'function') {
  const orig = globalThis.crypto ?? {};
  Object.defineProperty(globalThis, 'crypto', {
    value: {
      ...orig,
      randomUUID: (): `${string}-${string}-${string}-${string}-${string}` => {
        return '10000000-1000-4000-8000-100000000000'.replace(
          /[018]/g,
          c => (Number(c) ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (Number(c) / 4)))).toString(16),
        ) as `${string}-${string}-${string}-${string}-${string}`;
      },
    },
    writable: true,
  });
}

import '@backstage/cli/asset-types';
import ReactDOM from 'react-dom/client';
import App from './App';
import '@backstage/ui/css/styles.css';

ReactDOM.createRoot(document.getElementById('root')!).render(App.createRoot());
