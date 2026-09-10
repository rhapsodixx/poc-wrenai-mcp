# Business rules for the sidora connection

Engineering-productivity data for the tiptip engineering team. Monthly snapshots per team member.

## Grain and time
- `month` in `mr_snapshots` and `cc_snapshots` is always the first day of the month.
- Data range as of Sep 2026: `mr_snapshots` Oct 2025 → Jul 2026, `cc_snapshots` Apr 2026 → Jul 2026.
- "Last full quarter" = `date_trunc('quarter', (select max(month) from mr_snapshots))`.
- A quarter is three `month` rows; use `date_trunc('quarter', month)` for quarterly rollups.

## Joins
- Anything "by team": `mr_snapshots`/`cc_snapshots` → `team_members` (team_member_id) → `groups` (group_id).
- `gitlab_groups` and `users` are standalone reference tables; do not join them to metrics.

## Headcount
- "Current" or "active" members: `team_members.deleted_at IS NULL` (soft delete). Keep deleted members for historical totals.
- `contract_end_date IS NOT NULL` marks a fixed-term contract.

## Metrics
- `mrs_created`, `mrs_merged`, `approvals_given`, `lines_adopted` are monthly counts: aggregate with SUM.
- `avg_time_to_merge_hours` and `avg_review_turnaround_hours` are per-member monthly means: aggregate with AVG, never SUM.
  They are NULL in every row today (sync does not fill them yet). If asked, say the data is not populated instead of guessing.
- Merge rate = `sum(mrs_merged) / nullif(sum(mrs_created), 0)`.

## Output
- Row limit is 1000; aggregate rather than dumping rows.
- Use model names from the MDL, never raw table names.
