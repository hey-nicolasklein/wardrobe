import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    host: true,
    port: 5174,
    allowedHosts: ['.ts.net'],
    proxy: {
      '/api': {
        target: 'http://localhost:4142',
        timeout: 20 * 60 * 1000,
        proxyTimeout: 20 * 60 * 1000,
      },
    },
  },
});
