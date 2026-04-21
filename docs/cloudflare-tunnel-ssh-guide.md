# Cloudflare Tunnel SSH 배포 가이드

22포트 인바운드를 전역 개방하지 않고, Cloudflare Tunnel을 통해 GitHub Actions에서 SSH로 서버에 배포하는 구조.

## 아키텍처

```
GitHub Actions → cloudflared access ssh → Cloudflare Edge → Tunnel → 서버 SSH(localhost:22)
```

이중 보호:

1. **Cloudflare Access Service Token** — 토큰 없으면 터널 접근 자체 차단
2. **SSH 키 인증** — 터널 통과해도 SSH 키 없으면 접속 불가

## 설정 순서

> **터널은 서버당 1개**이다. 프로젝트별로 만들지 않는다. 이름은 서버 호스트네임 기준으로 짓는다.

### 1단계: Cloudflare Zero Trust — 터널 생성

1. Zero Trust → 네트워크 → 커넥터 → **터널 생성**
2. 터널 이름: 서버 호스트네임 (예: `codiworks-web-03`)
3. 커넥터 유형: `cloudflared`
4. 서버에 설치할 명령어가 자동 생성됨 → **6단계**에서 서버에서 실행
5. **Public Hostname** 추가:
   - Subdomain: `ssh-tunnel` (또는 원하는 이름)
   - Domain: 사용할 도메인 선택
   - Type: `SSH`
   - URL: `localhost:22`

### 2단계: Cloudflare Access — Application 생성

1. Zero Trust → Access → 응용 프로그램 → **Create new application**
2. **Self-hosted** 선택
3. Application domain: `ssh-tunnel.{domain}`
4. **Browser rendering(브라우저 SSH) 반드시 비활성화**
   - 활성화하면 cloudflared CLI의 WebSocket 연결이 차단됨

### 3단계: Cloudflare Access — Service Token 발급

1. Zero Trust → Access → 서비스 인증 → **Service Token 생성**
2. 발급된 값 기록:
   - `CF_ACCESS_CLIENT_ID` (Client ID)
   - `CF_ACCESS_CLIENT_SECRET` (Client Secret)

### 4단계: Cloudflare Access — 정책 설정

1. 응용 프로그램 → 해당 앱 → **정책** 탭
2. 정책 추가:
   - Action: **Service Auth**
   - Include: Service Token → 해당 토큰 선택

> **주의: Action을 `Allow`로 설정하면 브라우저 로그인을 요구하여 CI/CD에서 실패한다. 반드시 `Service Auth`를 선택할 것.**

### 5단계: Cloudflare WAF — 예외 규칙 추가 (필수!)

Cloudflare WAF/Bot Fight Mode는 GitHub Actions IP(데이터센터)를 봇으로 분류하여 JavaScript Challenge를 발동시킨다.
이 단계를 빠뜨리면 `websocket: bad handshake` 에러가 발생한다.

1. Cloudflare 대시보드 (일반, Zero Trust 아님) → 해당 도메인 → **보안 → WAF**
2. **사용자 지정 규칙** 추가:
   - 규칙 이름: `SSH Tunnel Allow`
   - 조건: **호스트 이름**이 `ssh-tunnel.{domain}`과 같음
   - 작업: **건너뛰기(Skip)** → 모든 남은 규칙 건너뛰기

### 6단계: 서버에 cloudflared 설치

1단계에서 대시보드가 자동 생성한 설치 명령을 서버에서 실행한다.

Rocky Linux에서 RPM repo GPG 키 오류가 발생할 경우 직접 설치:

```bash
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm -o /tmp/cloudflared.rpm
sudo rpm -ivh /tmp/cloudflared.rpm
```

Ubuntu/Debian:

```bash
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

설치 후 서비스 상태 확인:

```bash
sudo systemctl status cloudflared
```

### 7단계: Infisical에 시크릿 추가

`/backend/github-actions/` 경로에 아래 변수를 추가한다:

| 키                        | 값                    | 설명                        |
| ------------------------- | --------------------- | --------------------------- |
| `BACK_SSH_TUNNEL_HOST`    | `ssh-tunnel.{domain}` | 터널 hostname               |
| `CF_ACCESS_CLIENT_ID`     | 3단계에서 발급        | Service Token Client ID     |
| `CF_ACCESS_CLIENT_SECRET` | 3단계에서 발급        | Service Token Client Secret |

### 8단계: GitHub Actions 워크플로우

기존 `appleboy/scp-action`, `appleboy/ssh-action`을 아래로 교체한다:

```yaml
- name: Install cloudflared
  run: |
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared

- name: Setup SSH via Cloudflare Tunnel
  run: |
    mkdir -p ~/.ssh
    echo "${{ steps.deploy-secrets.outputs.ssh_key }}" > ~/.ssh/deploy_key
    chmod 600 ~/.ssh/deploy_key
    {
      echo "Host deploy-server"
      echo "  HostName ${BACK_SSH_TUNNEL_HOST}"
      echo "  User ${BACK_SERVER_USER}"
      echo "  IdentityFile ~/.ssh/deploy_key"
      echo "  StrictHostKeyChecking no"
      echo "  UserKnownHostsFile /dev/null"
      echo "  ProxyCommand cloudflared access ssh --hostname %h --id ${CF_ACCESS_CLIENT_ID} --secret ${CF_ACCESS_CLIENT_SECRET}"
    } > ~/.ssh/config

- name: Deploy to server via SCP
  run: |
    scp -F ~/.ssh/config {source_file} deploy-server:{target_dir}/

- name: Run deploy script on server
  run: |
    ssh -F ~/.ssh/config deploy-server "cd {deploy_dir} && sh {deploy_script}"
```

> `{source_file}`, `{target_dir}`, `{deploy_dir}`, `{deploy_script}`는 프로젝트에 맞게 치환한다.

### 9단계: 서버 방화벽에서 22포트 인바운드 차단

모든 것이 정상 동작 확인 후 22포트 전역 개방 규칙을 제거한다.

## 트러블슈팅

| 증상                               | 원인                                        | 해결                                  |
| ---------------------------------- | ------------------------------------------- | ------------------------------------- |
| `websocket: bad handshake`         | WAF/Bot Fight Mode가 GitHub Actions IP 차단 | **5단계** WAF 예외 규칙 추가          |
| `302` 리다이렉트 + 로그인 페이지   | Access 정책 Action이 `Allow`                | **4단계** `Service Auth`로 변경       |
| 서버 로그에 연결 흔적 없음         | Cloudflare Edge에서 차단                    | WAF 이벤트 로그 확인                  |
| `cloudflared service install` 실패 | config.yml 경로 못 찾음                     | `/etc/cloudflared/`에 설정 파일 복사  |
| ProxyCommand에서 환경변수 미인식   | SSH가 별도 프로세스로 ProxyCommand 실행     | `--id`, `--secret` 플래그로 직접 전달 |

## 주의사항

- **터널은 서버당 1개** — 하나의 터널에 여러 hostname(서비스)을 매핑할 수 있다
- **Access Application의 Browser SSH rendering은 반드시 비활성화** — 활성화 시 cloudflared CLI 연결 차단
- **WAF 예외 규칙은 필수** — GitHub Actions Runner는 데이터센터 IP이므로 봇으로 분류된다
- **ProxyCommand 환경변수 전달 불가** — SSH가 별도 프로세스로 실행하므로 `--id`, `--secret` 플래그로 값을 직접 전달해야 한다
- **Cloudflare Zero Trust Free 플랜은 50명까지 무료** — Service Token은 사용자 수에 포함되지 않음
