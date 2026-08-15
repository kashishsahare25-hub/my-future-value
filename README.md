# My Future Value

Here's the revised prompt with the demo-data seed removed — the backend now expects only real, user-entered transactions (via the Ledger / Quick Add forms you'll build on the frontend):

I want you to build ONLY the backend for this app (Supabase — tables, RLS, views, and one edge function). Do not generate or modify any frontend UI/pages yet — I'll handle that separately.

CONTEXT
RealCost is a personal finance app that converts spending into "hours of work" and "future value if invested instead." Formulas:
- hours_traded = transaction.amount / profile.hourly_rate
- future_value = transaction.amount * (1 + profile.expected_return) ^ profile.projection_years

All data in this app comes from real transactions the user enters themselves — there is no demo/sample data to seed.

Set up the following:

1. TABLES

profiles (one row per user, id = auth.users.id, FK on delete cascade)
- hourly_rate numeric, default 500
- annual_salary numeric, nullable
- expected_return numeric, default 0.07, must be between 0 and 0.15
- projection_years int, default 20
- onboarding_complete boolean, default false
- created_at, updated_at timestamptz

categories (lookup table)
- id serial primary key
- name text unique
- sort_order int
Seed with: Food, Shopping, Transport, Subscriptions, Entertainment, Other
(This is reference/lookup data, not user demo data — it's fine to seed.)

transactions
- id uuid primary key default gen_random_uuid()
- user_id uuid, FK to auth.users, on delete cascade
- name text, not null
- category_id int, FK to categories
- amount numeric, not null, check amount > 0
- occurred_at date, default current_date
- recurring boolean, default false
- recurrence_interval text, check in ('monthly','yearly'), nullable
- deleted_at timestamptz, nullable (soft delete)
- created_at timestamptz, default now()
Add indexes on (user_id, occurred_at desc) and (user_id, category_id).

subscriptions
- id uuid primary key default gen_random_uuid()
- user_id uuid, FK to auth.users, on delete cascade
- transaction_id uuid, FK to transactions, on delete cascade
- status text, check in ('active','reminder_set','cancelled'), default 'active'
- reminder_date date, nullable
- updated_at timestamptz, default now()

2. ROW LEVEL SECURITY
Enable RLS on profiles, transactions, and subscriptions. For each, add a policy so a user can only select/insert/update/delete their own rows, matched on auth.uid() = user_id (or auth.uid() = id for profiles).

3. VIEWS
Create transactions_with_impact: joins transactions (excluding soft-deleted rows) to profiles, adding computed columns hours_traded = amount / hourly_rate and future_value = amount * power(1 + expected_return, projection_years).

Create subscription_shock: aggregates transactions where recurring = true per user, returning monthly_recurring_total (sum of amount) and long_term_projection (monthly_recurring_total * 12 * projection_years, compounded at expected_return using the same power formula).

Create category_monthly_summary: groups transactions by user_id, category_id, and month (date_trunc('month', occurred_at)), returning total_amount and total_hours (total_amount / hourly_rate).

4. FUNCTIONS
Create a SQL function derive_hourly_rate(annual_salary numeric, hours_per_week numeric default 40, weeks_per_year numeric default 52) that returns annual_salary / (hours_per_week * weeks_per_year). Used during onboarding for the salary-to-hourly-rate conversion.

Create an edge function whatif-projection that accepts a monthly_reduction number, reads the caller's profile (hourly_rate, expected_return, projection_years), and returns an array of {year, projected_value} at year 0, 5, 10, 15, and up to projection_years, where projected_value = monthly_reduction * (1 + expected_return) ^ year. Require authentication and only return the caller's own projection.

Do not build any frontend components, pages, or styling in this step — just confirm the schema, policies, views, and functions are created and working. Since there's no demo data, testing should be done by manually inserting a couple of real-looking transactions through the Supabase table editor or a test API call.


The only real content change from before: no demo_data_loaded / is_demo fields, no seed function, and the onboarding flow now assumes a first-time user with zero transactions until they add their own — so make sure your frontend's empty states (Dashboard, Ledger, Insights) handle a genuinely empty transactions table gracefully.

This project was built with [Lovable](https://lovable.dev).

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/a71dfd0c-6553-4691-ba9f-46747095a1c3).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```
