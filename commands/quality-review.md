Run a comprehensive code quality audit on the current project. $ARGUMENTS

## Instructions

Follow these steps precisely. Do NOT skip any step or dimension.

### Step 1: Discovery (auto-detect)

Before auditing, understand the project:

a. **Tech stack** — identify from package files (package.json, pyproject.toml, Cargo.toml, go.mod, pom.xml, etc.)
b. **Architecture style** — infer from directory structure (layered, MVC, microservices, monolith, etc.)
c. **Coding guidelines** — find and read any guideline files (CLAUDE.md, CONTRIBUTING.md, .eslintrc, .editorconfig, styleguide, etc.)
d. **Tests** — locate test files, identify testing framework and patterns
e. **Project size** — count source files and estimate LOC to calibrate expectations

Present a brief discovery summary before proceeding to the audit.

For large projects (more than ~200 source files), run each of the 3 dimensions in its own
parallel subagent — each returns its tables, evidence, and scores in the format below — and
consolidate into the single report. A single context cannot hold a large codebase; fan-out
keeps evidence quality up.

### Step 2: Audit — 3 Dimensions

#### Dimension 1: Modularity & SOLID

Score each principle 1–10 with specific evidence from the code. If a principle does not apply
to the project's paradigm (e.g., Liskov Substitution or Interface Segregation in a codebase
with no subtyping or interfaces), mark it **N/A** with a one-line justification instead of
forcing a score; N/A rows are excluded from the dimension mean.

| Principle | What to evaluate |
|-----------|-----------------|
| **S** Single Responsibility | Does each class/module have one reason to change? Look for god classes, mixed concerns |
| **O** Open/Closed | Can behavior be extended without modifying existing code? Look for factory patterns, plugin architectures, strategy patterns |
| **L** Liskov Substitution | Do subtypes honor their parent contracts? Look for interface violations, unexpected overrides |
| **I** Interface Segregation | Are interfaces/ABCs focused? Do consumers depend only on what they use? |
| **D** Dependency Inversion | Do high-level modules depend on abstractions? Look for concrete dependencies, tight coupling |

After the table, include:
- **Architecture Highlights** — what's working well and should be preserved
- **Improvement Opportunities** — specific, actionable suggestions

#### Dimension 2: Guidelines & Policy Adherence

Evaluate against the project's own documented guidelines. If no guidelines exist, evaluate against industry-standard practices for the detected tech stack.

Check these categories (adapt to the stack):

| Category | What to evaluate |
|----------|-----------------|
| Documentation | Module/file docs, public API docs, inline comments (why not what) |
| Naming | Descriptive names, consistent conventions, units in variable names |
| Type safety | Type hints/annotations, generics usage, strict mode |
| Security | No eval/exec, no hardcoded secrets, input validation, dependency safety |
| Test conventions | Naming patterns, coverage of critical paths, regression tests for bugs |
| Code organization | Import structure, file size limits, logical grouping |

Rate each as: **Perfect** / **Excellent** / **Minor gap** / **Major gap** — with specific examples.

Give an overall dimension score 1–10.

#### Dimension 3: Changeability & Debuggability

Score each sub-dimension 1–10 with evidence:

| Sub-dimension | What to evaluate |
|---------------|-----------------|
| **Changeability** | How easy is it to add a feature or swap a component? Look for coupling, hardcoded values |
| **Debuggability** | Are errors observable? Logging quality, stack traces, error context |
| **Testability** | Can components be tested in isolation? Dependency injection, mockability |
| **Error Handling** | Are errors caught at the right level? Graceful degradation, user-facing messages |
| **State Management** | Is state centralized and observable? Race conditions, dual update paths |
| **Configuration** | External config support, environment handling, sensible defaults |
| **Code Organization** | File structure, import hygiene, no circular dependencies, largest file size |

After the table, include:
- **Key Risks** — top 3 risks that could cause real problems

### Step 3: Output Format

Structure the output as follows:

```
# [Project Name] — Code Quality Review

**Date:** [YYYY-MM-DD]

## Context
[Brief project description + discovery summary from Step 1]

---

## 1. Modularity & SOLID — Score: X/10
[SOLID table + highlights + improvements]

---

## 2. Guidelines & Policy Adherence — Score: X/10
[Guidelines table + bottom line]

---

## 3. Changeability & Debuggability — Score: X/10
[Sub-dimensions table + key risks]

---

## Overall Summary

| Dimension | Score |
|-----------|-------|
| Modularity & SOLID | **X/10** |
| Guidelines & Policy | **X/10** |
| Changeability & Debuggability | **X/10** |
| **Overall** | **X/10** |

### Top 5 Actionable Improvements (Priority Order)
1. ...
2. ...
3. ...
4. ...
5. ...

### What NOT to Change
- [Things that are working well and should be preserved]
```

## Scoring Rubric

Use this rubric consistently:

| Score | Meaning |
|-------|---------|
| 9–10  | Exemplary — could serve as a teaching reference |
| 7–8   | Good — minor issues, no structural problems |
| 5–6   | Adequate — works but has clear improvement areas |
| 3–4   | Concerning — structural issues that impede development |
| 1–2   | Critical — fundamental problems requiring immediate action |

A dimension's score is the arithmetic mean of its sub-scores (N/A rows excluded), rounded to
one decimal. The overall score is the average of the 3 dimension scores, rounded to one decimal.

## Trend Comparison (optional)

If $ARGUMENTS contains "compare" or a previous review file exists in the project (e.g., `docs/code-quality-review-*.md`), add a comparison section. Compare against the lexicographically latest previous file — ISO dates make lexicographic order chronological:

```
## Trend vs Previous Review ([previous date])

| Dimension | Previous | Current | Delta |
|-----------|----------|---------|-------|
| Modularity & SOLID | X/10 | Y/10 | +/-Z |
| Guidelines & Policy | X/10 | Y/10 | +/-Z |
| Changeability & Debuggability | X/10 | Y/10 | +/-Z |
| **Overall** | **X/10** | **Y/10** | **+/-Z** |

### Previous Improvements — Status
- [Improvement 1] — Addressed / Partially addressed / Not addressed
- ...
```

## Rules

- Do NOT skip any dimension or sub-dimension (marking a principle N/A with a one-line justification, per the Dimension 1 rule, is allowed; silent skipping is not)
- Do NOT give scores without citing specific evidence from the code (file names, patterns, examples)
- Do NOT inflate scores — be honest and calibrated
- Do NOT suggest improvements for things that are already working well — include a "What NOT to Change" section
- Save the review output to `docs/code-quality-review-YYYY-MM-DD.md` (ISO date). Create `docs/` if missing. A same-day rerun overwrites the same file
