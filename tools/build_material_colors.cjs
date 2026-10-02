// Run with esbuild@0.25.12 available in NODE_PATH. Source and license are pinned.
const esbuild = require('esbuild');
const path = require('node:path');
esbuild.buildSync({
  entryPoints: [path.resolve(__dirname, '../third_party/material_colors/bridge.ts')],
  bundle: true, minify: true, format: 'iife', target: 'es2020',
  outfile: path.resolve(__dirname, '../web/material_colors.js'),
  legalComments: 'eof',
});
