# Project Name

> (프로젝트 설명을 여기에 작성)

## Architecture
See [ARCHITECTURE.md](ARCHITECTURE.md) for the full domain map.

## Documentation
- [Design Docs](docs/design-docs/index.md) — architectural decisions and core beliefs
- [Execution Plans](docs/exec-plans/) — active and completed work plans
- [Product Specs](docs/product-specs/index.md) — feature specifications
- [References](docs/references/) — external library docs for LLMs

## Domain Guides
- [Frontend](docs/FRONTEND.md) — frontend architecture and patterns
- [Security](docs/SECURITY.md) — security policies and threat model
- [Product Sense](docs/PRODUCT-SENSE.md) — product thinking framework

## Quality & Planning
- [Quality Score](docs/QUALITY-SCORE.md) — per-domain quality grades
- [Code Review](docs/CODE-REVIEW.md) — review standards and checklist
- [Plans](docs/PLANS.md) — planning conventions
- [Tech Debt](docs/exec-plans/tech-debt-tracker.md) — known debt tracker

## Project Structure

```
apps/
├── front/    # Frontend
└── back/     # Backend
```

## Quick Rules

<!-- TODO: 프로젝트 규칙 확정 후 작성 -->

## Agent Configuration
- Multi-agent: oh-my-agent (`.agents/`)
- MCP: Serena (`.agents/mcp.json`)
- API contracts: `.agents/results/api-ready.md`
- Agent results: `.agents/results/`

<!-- MANUAL: Notes below this line are preserved on regeneration -->
