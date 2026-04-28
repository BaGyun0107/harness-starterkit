# Cloudflare Tunnel SSH 배포 가이드

22포트 인바운드를 전역 개방하지 않고, Cloudflare Tunnel을 통해 GitHub Actions에서 SSH로 서버에 배포하는 구조.

## 아키텍처

```
GitHub Actions → cloudflared access ssh → Cloudflare Edge → Tunnel → 서버 SSH(localhost:22)
```

이중 보호:

1. **Cloudflare Access Service Token** — 토큰 없으면 터널 접근 자체 차단
2. **SSH 키 인증** — 터널 통과해도 SSH 키 없으면 접속 불가

## 핵심 규칙

- **터널은 서버당 1개** — 프로젝트별로 만들지 않는다
- **Public Hostname은 터널당 고유** — 같은 hostname에 2개 이상의 터널을 연결하면 Cloudflare가 랜덤 라우팅하여 다른 서버로 갈 수 있다
- **서버 이름 기준으로 subdomain을 짓는다** — `ssh-web-03.example.com`, `ssh-web-04.example.com`
- **Service Token은 도메인 단위로 재사용** — `Shared-Secrets/cloudflare/{domain}/{subdomain}`에 저장

## 리소스 관계도

```
Infisical Shared-Secrets
└── cloudflare/
    ├── example.com/        ← 도메인별 Service Token
    │     ├── CF_ACCESS_CLIENT_ID
    │     └── CF_ACCESS_CLIENT_SECRET
    └── example2.com/
          ├── CF_ACCESS_CLIENT_ID
          └── CF_ACCESS_CLIENT_SECRET

Zero Trust (example.com)
├── Service Token (도메인당 1개, Shared-Secrets에서 관리)
│
├── 서버 web-03
│     ├── 터널: web-03                          (서버당 1개)
│     │     └── Public Hostname: ssh-web-03.example.com → ssh://localhost:22
│     ├── Application: ssh-web-03.example.com   (hostname당 1개)
│     │     └── 정책: Service Auth → Service Token
│     ├── WAF 예외: ssh-web-03.example.com      (hostname당 1개)
│     └── 배포 프로젝트들 (SSH_TUNNEL_HOST 공유)
│           ├── project-A  →  BACK_SSH_TUNNEL_HOST=ssh-web-03.example.com
│           └── project-B  →  BACK_SSH_TUNNEL_HOST=ssh-web-03.example.com
│
└── 서버 web-04
      ├── 터널: web-04
      │     └── Public Hostname: ssh-web-04.example.com → ssh://localhost:22
      ├── Application: ssh-web-04.example.com
      ├── WAF 예외: ssh-web-04.example.com
      └── 배포 프로젝트들
            └── project-C  →  BACK_SSH_TUNNEL_HOST=ssh-web-04.example.com
```

## 리소스별 재사용 범위

| 리소스              | 범위           | 서버 추가 시                     | 저장 위치                                        |
| ------------------- | -------------- | -------------------------------- | ------------------------------------------------ |
| **Service Token**   | 도메인당 1개   | 같은 도메인이면 재사용           | `Shared-Secrets/cloudflare/{domain}/{subdomain}` |
| **터널**            | 서버당 1개     | 새로 생성                        | Cloudflare 대시보드                              |
| **Application**     | hostname당 1개 | 새로 생성                        | Cloudflare 대시보드                              |
| **WAF 예외 규칙**   | hostname당 1개 | 새로 추가 (와일드카드 시 불필요) | Cloudflare 대시보드                              |
| **SSH_TUNNEL_HOST** | 서버당 1개     | 같은 서버면 재사용               | 프로젝트별 Infisical                             |

## 시나리오별 가이드

### 시나리오 A: 같은 서버에 새 프로젝트 추가

이미 터널이 설정된 서버에 새 프로젝트를 배포하는 경우. **가장 흔한 케이스.**

**해야 할 것:** 프로젝트 Infisical에 기존 값 입력만

| 키                        | 값                                                  | 출처                                             |
| ------------------------- | --------------------------------------------------- | ------------------------------------------------ |
| `BACK_SSH_TUNNEL_HOST`    | 기존 서버의 hostname (예: `ssh-web-03.example.com`) | 기존 프로젝트에서 복사                           |
| `CF_ACCESS_CLIENT_ID`     | 기존 값                                             | `Shared-Secrets/cloudflare/{domain}/{subdomain}` |
| `CF_ACCESS_CLIENT_SECRET` | 기존 값                                             | `Shared-Secrets/cloudflare/{domain}/{subdomain}` |
| `BACK_SSH_PRIVATE_KEY`    | 새로 생성                                           | SSH 키 생성 → 서버에 공개키 등록                 |

### 시나리오 B: 새 서버 추가

새 서버에 처음 배포하는 경우. **1~7단계 실행.**

| 단계  | 작업               | 분기                                                                        |
| ----- | ------------------ | --------------------------------------------------------------------------- |
| 1단계 | 터널 생성          | 항상 실행                                                                   |
| 2단계 | Service Token 발급 | 같은 도메인 → **건너뛰기** (Shared-Secrets에 이미 있음)                     |
|       |                    | 새 도메인 → 발급 후 `Shared-Secrets/cloudflare/{domain}/{subdomain}`에 저장 |
| 3단계 | Application 생성   | 항상 실행                                                                   |
| 4단계 | WAF 예외 규칙      | 와일드카드 규칙이면 **건너뛰기**, 아니면 새 hostname 추가                   |
| 5단계 | 서버에 설치        | 항상 실행 (cloudflared 설치 + 서비스 등록)                                  |
| 6단계 | Infisical 시크릿   | 항상 실행                                                                   |

---

## 설정 단계 상세

### 1단계: 터널 생성

1. Zero Trust → 네트워크 → 커넥터 → **터널 생성**
2. 터널 이름: 서버 호스트네임 (예: `web-03`)
3. 커넥터 유형: `cloudflared`
4. 서버에 설치할 명령어가 자동 생성됨 → **5단계**에서 서버에서 실행
5. **Public Hostname** 추가:
   - Subdomain: 서버 고유 이름 (예: `ssh-web-03`)
   - Domain: 사용할 도메인 선택
   - Type: `SSH`
   - URL: `ssh://localhost:22` (sshd가 리스닝하는 포트)

> **주의: 같은 subdomain+domain 조합을 다른 터널에서 이미 사용 중이면 안 된다.** 같은 hostname에 2개 터널이 연결되면 Cloudflare가 랜덤 라우팅하여 의도하지 않은 서버로 접속된다.

### 2단계: Service Token 발급

`Shared-Secrets/cloudflare/{domain}/{subdomain}`에 이미 `CF_ACCESS_CLIENT_ID`, `CF_ACCESS_CLIENT_SECRET`이 있으면 **건너뛴다.**

새 도메인인 경우:

1. Zero Trust → Access → 서비스 자격 증명 → **Service Token 생성**
2. 발급된 값을 **Infisical `Shared-Secrets/cloudflare/{domain}/{subdomain}`에 저장**:
   - `CF_ACCESS_CLIENT_ID` (Client ID)
   - `CF_ACCESS_CLIENT_SECRET` (Client Secret)

### 3단계: Application 생성

1. Zero Trust → Access → 응용 프로그램 → **Create new application**
2. **Self-hosted** 선택
3. Application domain: `ssh-web-03.{domain}` (1단계의 hostname과 일치)
   4-1. (신규 정책 생성 시) Access policies: Create new policy -> Action: Service Token -> 2단계에서 생성한 토큰 선택
   -> Policy details
   Policy Name: (이 부분은 임의로 설정)
   Action: **Service Auth** > **주의: Action을 `Allow`로 설정하면 브라우저 로그인을 요구하여 CI/CD에서 실패한다. 반드시 `Service Auth`를 선택할 것.**
   4-2. (기존 정책 사용 시) Access policies: Add current policies -> 클릭
4. **Browser rendering(브라우저 SSH) 반드시 비활성화**
   - 활성화하면 cloudflared CLI의 WebSocket 연결이 차단됨

### 4단계: WAF 예외 규칙 추가

Cloudflare WAF/Bot Fight Mode는 GitHub Actions IP(데이터센터)를 봇으로 분류하여 JavaScript Challenge를 발동시킨다.
이 단계를 빠뜨리면 `websocket: bad handshake` 에러가 발생한다.

1. Cloudflare 대시보드 (일반, Zero Trust 아님) → 해당 도메인 → **보안 → WAF**
2. **사용자 지정 규칙** 추가:
   - 규칙 이름: `SSH Tunnel Allow`
   - 조건: **호스트 이름**이 `ssh-web-03.{domain}`과 같음
   - 작업: **건너뛰기(Skip)** → 모든 남은 규칙 건너뛰기

> **팁:** 와일드카드로 `ssh-*.{domain}` 패턴을 사용하면 서버 추가 시 WAF 규칙을 매번 수정하지 않아도 된다. 조건을 "호스트 이름이 `ssh-`로 시작"으로 설정.

### 5단계: 서버에 cloudflared 설치 + 터널 서비스 등록

#### 5-A. 바이너리 설치

1단계의 대시보드가 자동 생성한 설치 명령에 포함되어 있지만, RPM repo GPG 키 오류가 발생할 경우 직접 설치:

Rocky Linux / RHEL:

```bash
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-x86_64.rpm -o /tmp/cloudflared.rpm
sudo rpm -ivh /tmp/cloudflared.rpm
cloudflared --version   # 설치 확인
```

Ubuntu/Debian:

```bash
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
```

#### 5-B. 터널 서비스 등록

바이너리 설치만으로는 터널이 동작하지 않는다. 1단계에서 생성한 터널의 토큰으로 systemd 서비스를 등록해야 한다.

1단계의 대시보드 화면에 표시된 명령을 실행한다. 형식:

```bash
sudo cloudflared service install <TUNNEL_TOKEN>
```

`<TUNNEL_TOKEN>`은 1단계에서 터널 생성 후 대시보드의 "커넥터 설치" 화면에 표시된다. `eyJ...` 형태의 긴 JWT 토큰이다.

- 만약, TUNNEL_TOKEN을 잃어버렸다면, 네트워크 > 커넥터 > 개요 > Add a connector 를 누르면 확인 가능하다.

이 명령이 수행하는 것:

- `cloudflared.service` systemd 유닛 등록 (토큰이 서비스 실행 인자로 포함됨)
- 서비스 자동 시작 + 부팅 시 자동 실행 활성화
- 별도 config 파일 생성 없음 — 터널 설정은 토큰(JWT)에 내장되어 있고, 대시보드에서 관리

#### 5-C. 서비스 상태 확인

```bash
sudo systemctl status cloudflared
# Active: active (running) 이면 정상

# 로그 확인 (문제 발생 시)
sudo journalctl -u cloudflared -f
```

대시보드에서도 커넥터 상태가 **Connected**로 표시되어야 한다.

#### 트러블슈팅: 서비스 등록 실패 시

```bash
# 이미 등록된 서비스가 있으면 먼저 제거
sudo cloudflared service uninstall
sudo cloudflared service install <TUNNEL_TOKEN>

# 수동 실행으로 에러 확인
cloudflared tunnel run --token <TUNNEL_TOKEN>
```

### 6단계: Infisical에 시크릿 추가

프로젝트의 `/{backend 또는 frontend}/github-actions/` 경로에 아래 변수를 추가한다:

| 키                        | 값                          | 출처                                             |
| ------------------------- | --------------------------- | ------------------------------------------------ |
| `BACK_SSH_TUNNEL_HOST`    | `ssh-web-03.{domain}`       | 1단계에서 설정한 hostname                        |
| `CF_ACCESS_CLIENT_ID`     | Service Token Client ID     | `Shared-Secrets/cloudflare/{domain}/{subdomain}` |
| `CF_ACCESS_CLIENT_SECRET` | Service Token Client Secret | `Shared-Secrets/cloudflare/{domain}/{subdomain}` |

> **CF 토큰은 프로젝트별로 복사하지 않는다.** 워크플로우에서 `Shared-Secrets/cloudflare/{domain}/{subdomain}/` 경로로 직접 조회한다.

## 트러블슈팅

| 증상                                   | 원인                                        | 해결                                      |
| -------------------------------------- | ------------------------------------------- | ----------------------------------------- |
| `websocket: bad handshake`             | WAF/Bot Fight Mode가 GitHub Actions IP 차단 | **5단계** WAF 예외 규칙 추가              |
| `302` 리다이렉트 + 로그인 페이지       | Access 정책 Action이 `Allow`                | **4단계** `Service Auth`로 변경           |
| 서버 로그에 연결 흔적 없음             | Cloudflare Edge에서 차단                    | WAF 이벤트 로그 확인                      |
| `Permission denied` + 호스트 키 불일치 | 같은 hostname에 터널 2개 연결 (랜덤 라우팅) | 터널당 고유 hostname 사용. 중복 경로 제거 |
| ProxyCommand에서 환경변수 미인식       | SSH가 별도 프로세스로 ProxyCommand 실행     | `--id`, `--secret` 플래그로 직접 전달     |

## 주의사항

- **같은 hostname에 터널 2개 연결 금지** — Cloudflare가 랜덤 라우팅하여 다른 서버로 접속됨. 서버마다 고유 subdomain 사용
- **Service Token은 도메인 단위** — `Shared-Secrets/cloudflare/{domain}/{subdomain}/`에 한 곳에서 관리. 프로젝트별로 중복 저장하지 않는다
- **Access Application의 Browser SSH rendering은 반드시 비활성화** — 활성화 시 cloudflared CLI 연결 차단
- **WAF 예외 규칙은 필수** — GitHub Actions Runner는 데이터센터 IP이므로 봇으로 분류된다
- **ProxyCommand 환경변수 전달 불가** — SSH가 별도 프로세스로 실행하므로 `--id`, `--secret` 플래그로 값을 직접 전달해야 한다
- **Cloudflare Zero Trust Free 플랜은 50명까지 무료** — Service Token은 사용자 수에 포함되지 않음
