# 모노레포 직접 배포 전환 가이드

현재 subtree split 방식(A)에서, 모노레포 직접 배포 방식(B)으로 전환하는 가이드.

## 현재 구조 (A: subtree split)

```
dev-liveview push
  → sync-repos.yml
    ├── subtree split → front-liveview (Vercel 자동 배포)
    └── subtree split → back-liveview → deploy-backend.yml → 서버 배포
```

**레포 3개**: dev-liveview, front-liveview, back-liveview

### 운영 규칙

- front-liveview, back-liveview에 **직접 push 금지**
- dev-liveview에서만 작업, sync-repos.yml이 자동 동기화
- 직접 push하면 --force-with-lease가 stale 에러로 실패함

### 한계

- 2단계 파이프라인 (sync → deploy)으로 복잡도 높음
- cross-repo 인증 (GitHub App 토큰) 필요
- sync 실패 시 배포 안 됨

---

## 전환 후 구조 (B: 모노레포 직접 배포)

```
dev-liveview push
  ├── Vercel: apps/front/ 변경 감지 → 자동 배포
  └── deploy-backend.yml: apps/back/ 변경 감지 → 직접 빌드+배포
```

**레포 1개**: dev-liveview만 사용

---

## 전환 절차

### 1단계: Vercel 재연결 (front)

1. Vercel 대시보드 → 기존 front-liveview 프로젝트 삭제 (또는 disconnect)
2. New Project → **dev-liveview** 레포 연결
3. Settings:
   - **Root Directory**: `apps/front`
   - **Framework Preset**: Next.js
   - **Build Command**: `npm run build` (또는 자동 감지)
4. Environment Variables 설정 (기존과 동일)
5. dev 브랜치 → Preview, main 브랜치 → Production 매핑 확인

### 2단계: 백엔드 배포 워크플로우 변경

`deploy-backend.yml`을 아래로 교체:

```yaml
# .github/workflows/deploy-backend.yml
name: Deploy Backend

on:
  push:
    branches: [main, dev]
    paths:
      - 'apps/back/**'

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.ref_name == 'main' && 'production' || 'development' }}
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '24'

      - name: Set environment variables
        run: |
          if [ "${{ github.ref_name }}" = "main" ]; then
            echo "DEPLOY_SERVER=${{ secrets.PRD_SERVER_HOST }}" >> $GITHUB_ENV
            echo "DEPLOY_USER=${{ secrets.PRD_SERVER_USER }}" >> $GITHUB_ENV
            echo "DEPLOY_DIR=${{ secrets.PRD_DEPLOY_DIR }}" >> $GITHUB_ENV
            echo "DEPLOY_SHELL=${{ secrets.PRD_SHELL_FILE }}" >> $GITHUB_ENV
            echo "ENV_NAME=.env.production" >> $GITHUB_ENV
          else
            echo "DEPLOY_SERVER=${{ secrets.DEV_SERVER_HOST }}" >> $GITHUB_ENV
            echo "DEPLOY_USER=${{ secrets.DEV_SERVER_USER }}" >> $GITHUB_ENV
            echo "DEPLOY_DIR=${{ secrets.DEV_DEPLOY_DIR }}" >> $GITHUB_ENV
            echo "DEPLOY_SHELL=${{ secrets.DEV_SHELL_FILE }}" >> $GITHUB_ENV
            echo "ENV_NAME=.env.development" >> $GITHUB_ENV
          fi

      - name: Create .env file
        run: printf '%s' "$ENV_FILE_CONTENT" > "apps/back/${{ env.ENV_NAME }}"
        env:
          ENV_FILE_CONTENT: ${{ github.ref_name == 'main' && secrets.PRD_ENV_FILE || secrets.DEV_ENV_FILE }}

      - name: Cache node_modules
        uses: actions/cache@v4
        with:
          path: apps/back/node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('apps/back/package-lock.json') }}

      - name: Install dependencies
        working-directory: apps/back
        run: npm ci --ignore-scripts

      - name: Generate Prisma client
        working-directory: apps/back
        run: npx prisma generate

      - name: Build
        working-directory: apps/back
        run: npm run build

      - name: Prune dev dependencies
        working-directory: apps/back
        run: npm prune --production

      - name: Compress build artifacts
        working-directory: apps/back
        run: |
          tar -czvf /tmp/deploy.tar.gz \
            dist node_modules ecosystem.config.js \
            "${{ env.ENV_NAME }}" package.json prisma

      - name: Deploy to server via SCP
        uses: appleboy/scp-action@v0.1.7
        with:
          host: ${{ env.DEPLOY_SERVER }}
          username: ${{ env.DEPLOY_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          source: /tmp/deploy.tar.gz
          target: ${{ env.DEPLOY_DIR }}

      - name: Run deploy script
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ env.DEPLOY_SERVER }}
          username: ${{ env.DEPLOY_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd ${{ env.DEPLOY_DIR }}
            sh ${{ env.DEPLOY_SHELL }}

      - name: Notify Slack
        if: always()
        continue-on-error: true
        uses: slackapi/slack-github-action@v2.0.0
        with:
          method: chat.postMessage
          token: ${{ secrets.SLACK_BOT_TOKEN }}
          payload: |
            {
              "channel": "${{ secrets.SLACK_CHANNEL || '#github-action-noti' }}",
              "text": "${{ job.status == 'success' && '✅' || '❌' }} *BACKEND ${{ job.status }}* (${{ github.ref_name == 'main' && 'production' || 'development' }})\nRepo: ${{ github.repository }}\nBranch: ${{ github.ref_name }}\nCommit: `${{ github.sha }}`\nBy: ${{ github.actor }}\n<${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}|View Run>"
            }
```

### 3단계: 시크릿 이전

back-liveview에 있던 시크릿을 **dev-liveview**로 이전:

```bash
# dev-liveview에 environment 생성
gh api -X PUT "repos/CODIWORKS-Engineer/dev-liveview/environments/development"
gh api -X PUT "repos/CODIWORKS-Engineer/dev-liveview/environments/production"

# 시크릿 이전 (값은 back-liveview에서 확인 후 재등록)
gh secret set SSH_PRIVATE_KEY --repo CODIWORKS-Engineer/dev-liveview < ~/.ssh/deploy-liveview-dev
gh secret set DEV_SERVER_HOST --repo CODIWORKS-Engineer/dev-liveview --env development --body "133.186.216.12"
gh secret set DEV_SERVER_USER --repo CODIWORKS-Engineer/dev-liveview --env development --body "rocky"
gh secret set DEV_DEPLOY_DIR --repo CODIWORKS-Engineer/dev-liveview --env development --body "/home/rocky"
gh secret set DEV_SHELL_FILE --repo CODIWORKS-Engineer/dev-liveview --env development --body "deploy-live-view-back-dev.sh"
gh secret set DEV_ENV_FILE --repo CODIWORKS-Engineer/dev-liveview --env development < .env.development
# ... production도 동일하게
```

### 4단계: 정리

```bash
# sync-repos.yml 삭제 (또는 front만 남기기)
rm .github/workflows/sync-repos.yml

# 배포 레포 아카이브 (삭제하지 않고 보존)
gh repo archive CODIWORKS-Engineer/back-liveview
# front-liveview는 Vercel 재연결 확인 후 아카이브
gh repo archive CODIWORKS-Vercel/front-liveview

# init-project.sh에서 back-* 레포 생성 로직 제거
# CLAUDE.md 배포 파이프라인 문서 업데이트
```

---

## 전환 시 주의사항

- Vercel 재연결 시 **기존 도메인 설정**이 해제될 수 있으므로 확인
- 시크릿 이전은 **값을 다시 입력**해야 함 (GitHub API로 시크릿 값 조회 불가)
- back-liveview를 바로 삭제하지 말고 **archive** 처리 (롤백 가능하도록)
- 전환 후 1~2주 모니터링하여 안정성 확인 후 archive

## 전환하지 않아도 되는 경우

- front org 분리(CODIWORKS-Vercel)가 반드시 필요한 경우
- 나중에 모노레포를 해체하고 독립 레포로 전환할 계획이 확실한 경우
- 현재 A 방식이 안정적으로 동작하고 있는 경우
