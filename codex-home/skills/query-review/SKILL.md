---
name: query-review
description: "Explain SQL or analytics queries top-down and validate whether they match the intended metric or business meaning. Use for query walkthroughs, semantic review, or questions such as \"이 쿼리 맞아?\". Do not use for execution-only requests, syntax-error-only debugging, performance tuning, or unrelated code review."
---

# Query Review

Explain what a query produces and verify whether its data population, grain, and calculations match the user's intent. Do not treat readability or valid syntax as proof of semantic correctness.

## Choose the mode

- **EXPLAIN:** When the user asks for a walkthrough or wants to proceed one block at a time, explain top-down and pause at the requested depth for questions.
- **REVIEW:** When the user asks whether a query is correct, give the structural explanation and semantic verdict in the same response. Do not force a separate syntax phase first.

Default to one query at a time for an interactive walkthrough. If the user explicitly requests a batch review, cover each query separately or group only queries that share the same semantic pattern.

## Read top-down

1. Identify the SQL dialect and the intended result. Ask only when missing context would materially change the verdict.
2. Read the final `SELECT` first. State the output columns and what one result row represents.
3. Split the query into 2-4 named blocks and trace their dependencies. Use a compact flow only when it materially clarifies several dependent blocks.
4. For each block, state its input population, output grain, and cardinality-changing operations.
5. Explain expression internals only when they affect meaning or the user asks.

Use a tiny before/after table or numeric example when it makes row collapse, duplication, or a ratio easier to see. Do not default to line-by-line narration.

## Validate semantics

Check the items that can change the answer:

- intended population and final aggregation grain;
- join cardinality, duplicate multiplication, and dropped unmatched rows;
- filter placement before or after joins and aggregation;
- `NULL` behavior, default values, and missing-data treatment;
- time column, timezone, and inclusive or exclusive boundaries;
- dialect-specific division, casts, window frames, and grouping behavior;
- consistency between the metric name, output format, and possible values.

For ratios and rates, also check whether the numerator is a subset of the denominator, whether cohort membership is mixed with period activity, and whether values above 100% or below 0 are structurally possible.

Inspect referenced fragments, schema, or sample data when the verdict depends on them. Mark unresolved assumptions as `[UNKNOWN: ...]`; never guess keys, grain, partitions, or business intent.

## Resolve findings

- In REVIEW mode, lead with `correct`, `conditionally correct`, `incorrect`, or `unknown`, followed by the evidence that controls the verdict.
- If the query is wrong, offer the smallest viable options and recommend one. Diagnosis does not authorize edits.
- Modify SQL only after the user explicitly asks or approves an option. Then preserve repository patterns and run the narrowest relevant verification.
- Do not silently rename a metric to make incorrect logic appear correct, or change business meaning without calling out the trade-off.

## Output shape

For EXPLAIN, present the final result and grain, the block-level data flow, and only the details needed for the user's next question.

For REVIEW, present:

1. verdict;
2. intended result versus actual result and grain;
3. semantic findings with evidence;
4. risks and unknowns;
5. fix options only when needed.
