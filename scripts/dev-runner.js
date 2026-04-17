#!/usr/bin/env node
/**
 * ═══════════════════════════════════════════════════════════════════════════
 * 로컬 개발 런타임 래퍼 — Infisical 연결 상태에 따라 자동 분기
 * ═══════════════════════════════════════════════════════════════════════════
 *
 * 목적:
 *   `npm run dev` 하나로 Infisical 연결 여부와 무관하게 동작시킨다.
 *
 * 동작:
 *   1. Infisical CLI 설치 + 로그인 + 유효한 .infisical.json(workspaceId) 이 모두 충족되면
 *      → `infisical run --path=/{app} -- <command>` 로 실행 (런타임 시크릿 주입)
 *   2. 하나라도 미충족이면
 *      → `<command>` 를 그대로 실행 (로컬 .env 파일 사용)
 *
 * 사용법:
 *   node <path-to>/scripts/dev-runner.js <app> <command...>
 *
 * 예시 (apps/front/package.json):
 *   "dev": "node ../../scripts/dev-runner.js frontend next dev"
 *
 * 예시 (apps/back/package.json):
 *   "dev": "node ../../scripts/dev-runner.js backend tsx watch src/server.ts"
 *
 * 인자:
 *   app     — Infisical 경로 세그먼트 (frontend | backend)
 *             `infisical run --path=/{app}` 로 전달됨
 *   command — 실행할 실제 개발 명령 (next dev, tsx watch 등)
 * ═══════════════════════════════════════════════════════════════════════════
 */

const { execSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const [, , app, ...cmd] = process.argv;

if (!app || cmd.length === 0) {
  console.error('[dev-runner] Usage: node dev-runner.js <app> <command...>');
  console.error('[dev-runner] Example: node dev-runner.js frontend next dev');
  process.exit(1);
}

/**
 * Infisical 사용 가능 여부를 체크한다.
 * 셋 중 하나라도 실패하면 false — 로컬 .env 로 fallback.
 *
 * @returns {boolean}
 */
function canUseInfisical() {
  // 1. CLI 설치 확인
  try {
    execSync('infisical --version', { stdio: 'ignore' });
  } catch {
    return { ok: false, reason: 'Infisical CLI 미설치' };
  }

  // 2. 로그인 상태 확인
  try {
    execSync('infisical user', { stdio: 'ignore' });
  } catch {
    return { ok: false, reason: 'Infisical 미로그인 (infisical login --domain=https://env.co-di.com)' };
  }

  // 3. .infisical.json 존재 + workspaceId 유효성
  const cfgPath = path.join(process.cwd(), '.infisical.json');
  if (!fs.existsSync(cfgPath)) {
    return { ok: false, reason: '.infisical.json 없음' };
  }

  try {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    if (!cfg.workspaceId || cfg.workspaceId.trim() === '') {
      return { ok: false, reason: '.infisical.json 의 workspaceId 비어있음' };
    }
  } catch (err) {
    return { ok: false, reason: `.infisical.json 파싱 실패: ${err.message}` };
  }

  return { ok: true };
}

const check = canUseInfisical();
const [binary, ...args] = check.ok
  ? ['infisical', 'run', `--path=/${app}`, '--', ...cmd]
  : cmd;

if (check.ok) {
  console.log(`[dev-runner] ✓ Infisical 연결됨 → /${app} 시크릿 주입`);
} else {
  console.log(`[dev-runner] ⚠ ${check.reason} → 로컬 .env 사용`);
}

const child = spawn(binary, args, {
  stdio: 'inherit',
  shell: process.platform === 'win32',
});

// 부모 프로세스 신호를 자식에게 그대로 전파 (Ctrl+C 등)
const forward = (sig) => () => {
  if (!child.killed) child.kill(sig);
};
process.on('SIGINT', forward('SIGINT'));
process.on('SIGTERM', forward('SIGTERM'));

child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  else process.exit(code ?? 0);
});

child.on('error', (err) => {
  console.error(`[dev-runner] 실행 실패: ${err.message}`);
  process.exit(1);
});
