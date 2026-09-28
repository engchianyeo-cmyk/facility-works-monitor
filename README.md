# FMWorks

FMWorks is an authenticated facilities-operations platform for reporting, authorizing, assigning, executing, and auditing maintenance work.

## Technology

Next.js 15, React 19, TypeScript, Tailwind CSS 4, Supabase Auth/PostgreSQL/RLS, Vercel, Vitest, and Playwright for isolated authenticated browser testing.

## Local development

```bash
npm install
npm run dev
```

Environment requirements are in [Security](docs/SECURITY.md). Never commit `.env.local` or expose the service-role key.

## Validation

```bash
npm run typecheck
npm run lint
npm test
npm run build
git diff --check
```

## Documentation

The single documentation repository is [docs/](docs/README.md). Start with the [PRD](docs/PRD.md), [Architecture](docs/ARCHITECTURE.md), [Data Model](docs/DATA_MODEL.md), [Workflow](docs/WORKFLOW.md), and [Security](docs/SECURITY.md).

Deployments are Git-driven. Schema changes use new numbered migrations tested in a disposable/non-production database; applied migrations are never rewritten.
