import esbuild from 'esbuild';
import { sassPlugin } from 'esbuild-sass-plugin';

const args = process.argv.slice(2)
const watch = args.includes('--watch')
const deploy = args.includes('--deploy')

const loader = {
  // Add loaders for images/fonts/etc, e.g. { '.svg': 'file' }
}

const plugins = [
  sassPlugin()
];

let opts = {
  entryPoints: ['./js/app.js', './css/app.css'],
  bundle: true,
  target: 'es2020',
  outdir: '../priv/static/assets',
  logLevel: 'info',
  loader,
  plugins
}

if (watch) {
  opts = {
    ...opts,
    sourcemap: 'inline'
  }
}

if (deploy) {
  opts = {
    ...opts,
    minify: true
  }
}

if (watch) {
  let ctx = await esbuild.context(opts);
  await ctx.watch();
} else {
  esbuild.build(opts);
}
