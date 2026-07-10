---
name: query-review
description: "Walk through a SQL/analytics query, especially Athena KPI or metric queries, one at a time, top-down. Break it into big blocks, explain each for a reader weak on SQL, then verify it semantically and business-wise: numerator vs denominator population, aggregation grain, cohort vs period-activity, greater-than-100-percent or negative possibilities. If it is wrong, offer options and apply the fix with a targeted test. Use when the user asks \"이 쿼리 맞아?\", \"쿼리 분석/검토\", \"쿼리 탑다운으로 설명\", \"쿼리 의미 확인\", \"쿼리별로 보자\", \"review this query\", \"is this query correct\", or similar, meaning they want to understand and validate a query, not just run it."
---

# Query Review Skill

The user wants to review analytics or SQL queries one by one and decide whether each truly expresses the statistic they want. They are often strong on backend but weak on SQL syntax, so explanations must be concrete, using analogies and tiny numeric examples instead of jargon. This is a reading and validation flow, not a bulk rewrite.

## Interaction Model

- Review one query per turn. Do not analyze several at once. Finish or park the current query before moving on.
- Let the user drive. Each query follows this fixed sequence:
  1. Target: agree on which query to look at. Recommend the simplest representative of a class first.
  2. Syntax Q&A: explain the mechanics top-down, then stop and let the user ask about anything they do not know. Answer those before judging.
  3. Semantics / business fit: only after syntax is clear, check whether it expresses the intended statistic.
  4. Resolve: if fine, say so and end the turn. If wrong, give options and a recommendation, get a decision, then apply.
- Do not jump to semantic critique while still in the syntax phase. Keep the phases clean.

## Top-Down Explanation

Peel from the outside in, not line-by-line:

- Level 0: what it ultimately produces. Read the final `SELECT` first, for example "the answer is numerator divided by denominator". Everything above is prep.
- Level 1: split into 2-4 named blocks. Usually each CTE is one block. Draw dependency arrows so the user sees the data flow, not just text.
- Level 2: inside each block, explain what this CTE turns its source rows into. State its output shape: columns and what one row means.
- Level 3: explain fragment internals only when asked, such as `MIN(concat(...))`, `substr`, `GROUP BY 1,2`, `COALESCE`, `LEFT JOIN`, or `NULLIF`.

Teaching aids that work for an SQL-weak reader:

- Analogies: CTE is a local variable inside a function; `GROUP BY` is an Excel pivot; string `MIN` over fixed-width `YYYYMMDD` works because lexical order matches chronological order.
- Tiny before/after tables: show 3-4 raw rows collapsing into the CTE output rows.
- Name dropped columns: after a `GROUP BY`, say exactly which fields survive, keys plus aggregates, and which are discarded.

## Semantic Checklist

Pull the query apart against the metric name and intended meaning:

- Same population on both sides? For any ratio or average, check whether numerator and denominator count the same set of entities. A frequent bug is numerator filtered on one event-time and denominator on another, creating different cohorts.
- Cohort vs period-activity: conversion, acceptance, and similar rates usually imply a cohort where numerator is a subset of denominator and should stay 0-100%. If it is "things that happened in range divided by other things in range", it can exceed 100% or go negative. Demonstrate with a concrete numeric example.
- Aggregation grain: does raw `COUNT(*)` over an event log over-count multiple rows per entity? Sibling metrics should dedupe consistently with `SELECT DISTINCT key` or a shared fragment.
- Time-filter target: when the same `{{DATE_FILTER}}` or date predicate appears twice, confirm which columns each instance binds to.
- Format sanity: percent should be at most 100% unless intentionally not; currency and durations should be non-negative.
- Mark anything not verified from code or data as `[UNKNOWN: ...]`. Do not guess schema, keys, or partition format.

## Cohort Fix Pattern

To turn a broken ratio into a real cohort rate, fix the denominator set, then make the numerator a subset via `LEFT JOIN`:

```sql
WITH
  cohort AS ( /* the in-range population, fixed */ ),
  ever_X AS ( /* entities that ever did X, time-unfiltered */ )
SELECT CAST(COUNT(x.key) AS DOUBLE) / NULLIF(COUNT(*), 0) AS value
FROM cohort c LEFT JOIN ever_X x USING (key...)
```

Say the tradeoff explicitly: a fresh cohort looks low because members have not converted yet. That is correct cohort behavior, not a bug.

## When A Fix Is Approved

- Present options as a small table: A recommended, B keep and relabel honestly, or do nothing. Include effort and risk, then ask for the decision. Do not apply before the user picks.
- Apply the smallest correct change. Reuse existing fragments and patterns already in the file.
- Use targeted tests only: `npx jest <path>` or the workspace's narrow runner. Never run the full suite for a one-file change. Add or adjust a regression guard that locks the intent, such as asserting cohort `LEFT JOIN` is present, not the literal SQL.
- Sync the docs or dashboard definition line if the metric meaning changed.

## Clero Metrics Notes

- Queries live in `Clero-Website/apps/ui/components/admin/metrics/queries/*.ts`.
- Shared grain fragments live in `queries/offer-sql.ts`: `JSON_ROW_FILTER`, `CAMPAIGN_ID` `COALESCE`, `distinctOfferKeys`, `offerFirstSeen`, and `matchedOfferCosts`. Reuse these instead of hand-writing predicates.
- The offer table is an event log: one row per offer per transition day. `PENDING` or creation is never exported, so "first transition" is the creation proxy. Treat any `PENDING`-dependent count as an approximation.
- Regression guards live in `queries/__tests__/queries.test.ts`. Run from `apps/ui`: `npx jest components/admin/metrics`.
- Status dashboard: `z_archived/04_metrics/00_dashboard.md`; status meanings are done, proxy-based done, and blocked by publisher gap.

## Anti-Patterns

- Line-by-line explanation with no top-down structure.
- Critiquing semantics while the user is still asking what a keyword does.
- Analyzing multiple queries in one turn, or preemptively rewriting before the user decides.
- Asserting query behavior from memory. Read the fragment or util that the template expands to, and confirm what `{{DATE_FILTER}}` becomes.
- Running the full test suite for a single-query change.
