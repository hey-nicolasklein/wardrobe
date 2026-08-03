const path = require('node:path');

const { getDefaultConfig } = require('expo/metro-config');

const config = getDefaultConfig(__dirname);
const contractsSource = `${path.resolve(__dirname, '../../packages/contracts/src')}${path.sep}`;

config.resolver.resolveRequest = (context, moduleName, platform) => {
  const isContractSource = context.originModulePath.startsWith(contractsSource);
  const isRelativeJavaScriptImport = /^\.\.?\/.*\.js$/.test(moduleName);

  if (isContractSource && isRelativeJavaScriptImport) {
    return context.resolveRequest(context, moduleName.slice(0, -3), platform);
  }

  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
