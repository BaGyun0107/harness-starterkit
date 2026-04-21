# mise 설치 가이드

프로젝트 루트의 `.mise.toml`에 정의된 Node.js 버전을 자동 관리하는 도구.

## 설치 + 활성화

```bash
# 1. mise 설치
brew install mise

# 2. 셸에 활성화 (최초 1회 — 이 단계가 없으면 mise install 해도 node가 안 잡힘)

# zsh 사용자:
echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
source ~/.zshrc

# bash 사용자:
echo 'eval "$(mise activate bash)"' >> ~/.bashrc
source ~/.bashrc

# 3. 프로젝트 디렉토리에서 설치
cd <project-root>
mise install

# 4. 확인
node --version   # .mise.toml에 정의된 버전 (예: v24.x.x)
which node       # ~/.local/share/mise/installs/node/... 경로여야 정상
```

## 자주 발생하는 문제

### `mise install` 했는데 `node`가 안 잡힘

**원인:** `mise activate`가 셸에 등록되지 않음. `brew install mise`만으로는 바이너리만 설치되고, 셸 훅(PATH 관리)이 활성화되지 않는다.

**확인:**
```bash
which node
# /usr/local/bin/node  ← 시스템 버전 (mise 미활성)
# ~/.local/share/mise/installs/node/24.x.x/bin/node  ← mise 정상 활성
```

**해결:** 위 2번 단계(`mise activate`) 실행 후 셸 재시작.

### `mise install` 실행 시 `No tools to install` 출력

**원인:** `.mise.toml`이 없는 디렉토리에서 실행. 프로젝트 루트에서 실행해야 한다.

### 새 터미널을 열 때마다 `node` 버전이 시스템 기본으로 돌아감

**원인:** `~/.zshrc` 또는 `~/.bashrc`에 `eval "$(mise activate ...)"` 가 없거나, nvm/fnm 같은 다른 버전 관리자와 충돌.

**해결:** `cat ~/.zshrc | grep mise` 로 활성화 라인이 있는지 확인. nvm을 쓰고 있었다면 nvm 관련 줄을 주석 처리.
