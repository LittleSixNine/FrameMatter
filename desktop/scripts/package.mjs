// SPDX-FileCopyrightText: 2026 LittleSixNine
// SPDX-License-Identifier: GPL-3.0-or-later
// Applies only to FrameMatter contributions; upstream notices are retained. See COPYRIGHT.txt.

// Linux packages only. Original Windows packaging is retained in private local research.
import { execFileSync } from 'node:child_process';
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const desktop = resolve(here, '..');
const tauriDir = join(desktop, 'src-tauri');
const repo = resolve(desktop, '..');
const buildDir = process.env.SPEKTRALAB_HOST_BUILD ?? join(repo, 'build');
const which = process.argv[2];

const TARGETS = {
  linux: {
    hostDir: join(buildDir, 'host-linux-x64'),
    exe: 'spektralab-host',
    triple: 'x86_64-unknown-linux-gnu',
    bundles: 'deb,appimage',
    out: 'linux',
    extra: [],
  },

};

function die(msg) {
  console.error(`package: ${msg}`);
  process.exit(1);
}

function stage(t) {
  const exe = join(t.hostDir, t.exe);
  if (!existsSync(exe)) die(`no engine host at ${exe}. Build it first (engine/host, see engine/docs/platforms/LINUX_WINDOWS.md); refusing to package an app without its engine.`);
  if (!existsSync(join(t.hostDir, 'engine'))) die(`no engine resources at ${join(t.hostDir, 'engine')}`);
  const bin = join(tauriDir, 'binaries');
  const staging = join(tauriDir, 'host-staging');
  rmSync(bin, { recursive: true, force: true });
  rmSync(staging, { recursive: true, force: true });
  mkdirSync(bin, { recursive: true });
  const ext = t.exe.endsWith('.exe') ? '.exe' : '';
  cpSync(exe, join(bin, `spektralab-host-${t.triple}${ext}`));
  cpSync(join(t.hostDir, 'engine'), join(staging, 'engine'), { recursive: true });
  if (existsSync(join(t.hostDir, 'licenses'))) cpSync(join(t.hostDir, 'licenses'), join(staging, 'licenses'), { recursive: true });
  const conf = {
    bundle: {
      externalBin: ['binaries/spektralab-host'],
      resources: { 'host-staging/engine': 'host/engine', 'host-staging/licenses': 'host/licenses' },
    },
  };
  const confPath = join(tauriDir, 'tauri.bundle.json');
  writeFileSync(confPath, JSON.stringify(conf, null, 2));
  return confPath;
}

function collect(t) {
  const release = join(desktop, 'release', t.out);
  rmSync(release, { recursive: true, force: true });
  mkdirSync(release, { recursive: true });
  // A cross build lands under target/<triple>/; a native one under target/release/.
  const roots = [join(tauriDir, 'target', 'release', 'bundle')];
  const found = [];
  for (const root of roots) {
    if (!existsSync(root)) continue;
    for (const kind of readdirSync(root)) {
      for (const f of readdirSync(join(root, kind))) {
        const p = join(root, kind, f);
        if (statSync(p).isFile() && /\.(deb|AppImage|rpm)$/.test(f)) {
          cpSync(p, join(release, f));
          found.push(`${join('release', t.out, f)} (${(statSync(p).size / 1e6).toFixed(1)} MB)`);
        }
      }
    }
  }
  console.log('package: wrote\n  ' + found.join('\n  '));
}

const t = TARGETS[which];
if (!t) die('usage: node scripts/package.mjs linux');
const conf = stage(t);
const env = { ...process.env };
env.NO_STRIP = env.NO_STRIP ?? 'true'; // linuxdeploy's strip cannot read newer ELF notes
execFileSync('npx', ['tauri', 'build', '--config', conf, '--bundles', t.bundles, ...t.extra], { cwd: desktop, stdio: 'inherit', env });
collect(t);
