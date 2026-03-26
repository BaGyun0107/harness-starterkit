# Planning Conventions

## Execution Plans

실행 계획은 `docs/exec-plans/`에 저장되며, 복잡한 작업의 진행 상황과 결정 로그를 추적한다.

### Lifecycle

1. **active/** — 진행 중인 계획
2. **completed/** — 완료된 계획 (맥락 보존)

### Plan Template

```markdown
# {Plan Name}

## Goal
{한 줄 목표}

## Scope
- [ ] Task 1
- [ ] Task 2

## Decisions Log
| Date | Decision | Rationale |
|------|----------|-----------|

## Progress
{진행 상황 업데이트}
```

### Rules

- 한 계획에 하나의 목표
- 결정 사항은 반드시 Decisions Log에 기록
- 완료 시 `completed/`로 이동

<!-- MANUAL: Notes below this line are preserved on regeneration -->
