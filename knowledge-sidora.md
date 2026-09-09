# Knowledge: `sidora`

Engineering-productivity data for the tiptip engineering team: who is on which team, how many GitLab merge
requests they create, merge and review each month, and how much Claude Code output they adopt.

- **Source:** Supabase project `wmkkjlxxiphgcynfgsjn` (ap-northeast-1), Postgres, schema `public`.
- **Wren profile:** `sidora`. MDL: [`wren-project/models/`](wren-project/models/), relationships in
  [`wren-project/relationships.yml`](wren-project/relationships.yml).
- **Grain:** monthly snapshots per team member. `month` is always the first day of the month.
- **Data range (Sep 2026):** `mr_snapshots` Oct 2025 → Jul 2026; `cc_snapshots` Apr 2026 → Jul 2026.

## Models

```
groups 1 ──< team_members 1 ──< mr_snapshots
                            1 ──< cc_snapshots
gitlab_groups   (standalone reference)
users           (app logins, standalone)
```

### `groups` — engineering teams
| column | type | meaning |
|---|---|---|
| id | UUID | primary key |
| name | TEXT | team name. Current values: Backend, Frontend, DevOps, Data, Quality, Product, Engineering, External |
| color | TEXT | hex colour used by the dashboard |
| created_at, updated_at | TIMESTAMPTZ | audit |

### `team_members` — people
| column | type | meaning |
|---|---|---|
| id | UUID | primary key |
| full_name | TEXT | display name |
| gitlab_email, gitlab_username | TEXT | GitLab identity used to attribute MRs |
| group_id | UUID | → `groups.id` |
| employee_type | TEXT | e.g. `full-time` (only value today) |
| contract_start_date, contract_end_date | DATE | nullable; `contract_end_date` set means fixed-term |
| deleted_at | TIMESTAMPTZ | **soft delete**. Active members have `deleted_at IS NULL` |
| created_at, updated_at | TIMESTAMPTZ | audit |

### `mr_snapshots` — monthly GitLab merge-request metrics per member
| column | type | meaning |
|---|---|---|
| id | UUID | primary key |
| team_member_id | UUID | → `team_members.id` |
| month | DATE | first day of the month |
| mrs_created | INT | MRs the member opened that month |
| mrs_merged | INT | MRs by the member that were merged that month |
| approvals_given | INT | reviews/approvals the member gave to others |
| avg_time_to_merge_hours | DECIMAL(8,2) | mean hours from MR open to merge. **Not populated yet: NULL in every row as of Sep 2026** |
| avg_review_turnaround_hours | DECIMAL(8,2) | mean hours to respond to review requests. **Not populated yet: NULL in every row as of Sep 2026** |
| synced_at | TIMESTAMPTZ | when this row was last pulled from GitLab |
| created_at, updated_at | TIMESTAMPTZ | audit |

### `cc_snapshots` — monthly Claude Code adoption per member
| column | type | meaning |
|---|---|---|
| id | UUID | primary key |
| team_member_id | UUID | → `team_members.id` |
| month | DATE | first day of the month |
| lines_adopted | INT | lines of Claude Code output the member accepted that month |
| created_at | TIMESTAMPTZ | audit |

### `gitlab_groups` — GitLab groups being synced
`id`, `gitlab_group_id` (GitLab numeric id), `name`, `path`, timestamps. Not joined to other models.

### `users` — dashboard logins
`id`, `auth_id` (Supabase Auth user), `name`, `email`, `role`, `last_login`, timestamps. Empty today. Not joined.

## Rules of thumb for the agent
- Join `mr_snapshots`/`cc_snapshots` to `team_members` to `groups` for anything "by team".
- Filter `team_members.deleted_at IS NULL` for "current" headcount; keep deleted members for historical totals.
- Averages in `mr_snapshots` are already per-member monthly means; aggregate them with `AVG`, never `SUM`.
  Until the sync fills them, any question about time-to-merge or review turnaround returns no rows; say so instead of guessing.
- A "quarter" is three `month` rows; use `date_trunc('quarter', month)`.
- Wren enforces a 1000-row limit; aggregate rather than dumping rows.

## Prompts to try

Each prompt below has a SQL the agent is expected to arrive at; all of them were run on 2026-09-09
(the contract-end one legitimately returns zero rows right now).

**"How many MRs did each team merge in the last full quarter?"**
```sql
select g.name as team, sum(m.mrs_merged) as merged
from mr_snapshots m
join team_members t on m.team_member_id = t.id
join groups g on t.group_id = g.id
where date_trunc('quarter', m.month) = date_trunc('quarter', (select max(month) from mr_snapshots))
group by 1 order by 2 desc
```

**"Show the monthly trend of merged MRs across the whole team."**
```sql
select month, sum(mrs_merged) as merged, sum(mrs_created) as created
from mr_snapshots group by 1 order by 1
```

**"Who are the top 5 reviewers by approvals given this year?"**
```sql
select t.full_name, g.name as team, sum(m.approvals_given) as approvals
from mr_snapshots m
join team_members t on m.team_member_id = t.id
join groups g on t.group_id = g.id
where m.month >= date_trunc('year', (select max(month) from mr_snapshots))
group by 1, 2 order by 3 desc limit 5
```

**"What is each team's merge rate (merged ÷ created) this year?"**
```sql
select g.name as team, sum(m.mrs_merged) as merged, sum(m.mrs_created) as created,
       round(100.0 * sum(m.mrs_merged) / nullif(sum(m.mrs_created), 0), 1) as merge_rate_pct
from mr_snapshots m
join team_members t on m.team_member_id = t.id
join groups g on t.group_id = g.id
where m.month >= date_trunc('year', (select max(month) from mr_snapshots))
group by 1 order by 4 desc
```

**"How is Claude Code adoption trending per team?"**
```sql
select c.month, g.name as team, sum(c.lines_adopted) as lines_adopted
from cc_snapshots c
join team_members t on c.team_member_id = t.id
join groups g on t.group_id = g.id
group by 1, 2 order by 1, 3 desc
```

**"Do members who adopt more Claude Code lines merge more MRs?"**
```sql
select t.full_name, sum(c.lines_adopted) as lines_adopted, sum(m.mrs_merged) as merged
from team_members t
join cc_snapshots c on c.team_member_id = t.id
join mr_snapshots m on m.team_member_id = t.id and m.month = c.month
group by 1 order by 2 desc
```

**"Whose contracts end in the next 90 days?"**
```sql
select full_name, contract_end_date
from team_members
where deleted_at is null and contract_end_date between current_date and current_date + interval '90 days'
order by contract_end_date
```

**"How many active members per team?"**
```sql
select g.name as team, count(*) as members
from team_members t join groups g on t.group_id = g.id
where t.deleted_at is null group by 1 order by 2 desc
```

## Adding business context
Put team-specific definitions (what counts as "active", target turnaround, holidays) in
`wren-project/knowledge/rules/general.md`; the MCP tool `get_instructions` serves that file to every agent.
Model and column descriptions belong in `wren-project/models/<model>/metadata.yml` under `properties.description`.
