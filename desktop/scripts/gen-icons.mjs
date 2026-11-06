// Generate every desktop icon from the approved FrameMatter artwork.
// Run from desktop/: npm run gen:icons
import { execFileSync } from 'node:child_process';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
execFileSync('npx', ['tauri', 'icon',
  resolve(here, '../../docs/assets/framematter-icon.png'),
  '-o', resolve(here, '../src-tauri/icons')], { stdio: 'inherit' });
