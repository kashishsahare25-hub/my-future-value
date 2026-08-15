-- PROFILES
CREATE TABLE public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  hourly_rate numeric NOT NULL DEFAULT 500,
  annual_salary numeric,
  expected_return numeric NOT NULL DEFAULT 0.07 CHECK (expected_return >= 0 AND expected_return <= 0.15),
  projection_years int NOT NULL DEFAULT 20,
  onboarding_complete boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.profiles TO authenticated;
GRANT ALL ON public.profiles TO service_role;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT TO authenticated USING (auth.uid() = id);
CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE TO authenticated USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
CREATE POLICY "Users can delete own profile" ON public.profiles FOR DELETE TO authenticated USING (auth.uid() = id);

-- CATEGORIES
CREATE TABLE public.categories (
  id serial PRIMARY KEY,
  name text NOT NULL UNIQUE,
  sort_order int NOT NULL DEFAULT 0
);
GRANT SELECT ON public.categories TO authenticated;
GRANT SELECT ON public.categories TO anon;
GRANT ALL ON public.categories TO service_role;
GRANT USAGE, SELECT ON SEQUENCE public.categories_id_seq TO service_role;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Categories are readable" ON public.categories FOR SELECT TO authenticated, anon USING (true);

INSERT INTO public.categories (name, sort_order) VALUES
  ('Food', 1), ('Shopping', 2), ('Transport', 3), ('Subscriptions', 4), ('Entertainment', 5), ('Other', 6);

-- TRANSACTIONS
CREATE TABLE public.transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name text NOT NULL,
  category_id int REFERENCES public.categories(id),
  amount numeric NOT NULL CHECK (amount > 0),
  occurred_at date NOT NULL DEFAULT current_date,
  recurring boolean NOT NULL DEFAULT false,
  recurrence_interval text CHECK (recurrence_interval IN ('monthly','yearly')),
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX transactions_user_occurred_idx ON public.transactions (user_id, occurred_at DESC);
CREATE INDEX transactions_user_category_idx ON public.transactions (user_id, category_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.transactions TO authenticated;
GRANT ALL ON public.transactions TO service_role;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own transactions" ON public.transactions FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own transactions" ON public.transactions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own transactions" ON public.transactions FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own transactions" ON public.transactions FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- SUBSCRIPTIONS
CREATE TABLE public.subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  transaction_id uuid NOT NULL REFERENCES public.transactions(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','reminder_set','cancelled')),
  reminder_date date,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX subscriptions_user_idx ON public.subscriptions (user_id);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.subscriptions TO authenticated;
GRANT ALL ON public.subscriptions TO service_role;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can view own subscriptions" ON public.subscriptions FOR SELECT TO authenticated USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own subscriptions" ON public.subscriptions FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own subscriptions" ON public.subscriptions FOR UPDATE TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own subscriptions" ON public.subscriptions FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- UPDATED_AT TRIGGERS
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;
CREATE TRIGGER profiles_set_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER subscriptions_set_updated_at BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- HELPER FUNCTION
CREATE OR REPLACE FUNCTION public.derive_hourly_rate(annual_salary numeric, hours_per_week numeric DEFAULT 40, weeks_per_year numeric DEFAULT 52)
RETURNS numeric LANGUAGE sql IMMUTABLE SET search_path = public AS $$
  SELECT CASE WHEN hours_per_week * weeks_per_year = 0 THEN NULL
              ELSE annual_salary / (hours_per_week * weeks_per_year) END;
$$;
GRANT EXECUTE ON FUNCTION public.derive_hourly_rate(numeric, numeric, numeric) TO authenticated, anon, service_role;

-- VIEWS (security_invoker so RLS applies as the caller)
CREATE VIEW public.transactions_with_impact WITH (security_invoker = on) AS
SELECT t.id, t.user_id, t.name, t.category_id, c.name AS category_name, t.amount,
       t.occurred_at, t.recurring, t.recurrence_interval, t.created_at,
       p.hourly_rate, p.expected_return, p.projection_years,
       t.amount / NULLIF(p.hourly_rate, 0) AS hours_traded,
       t.amount * power(1 + p.expected_return, p.projection_years) AS future_value
FROM public.transactions t
JOIN public.profiles p ON p.id = t.user_id
LEFT JOIN public.categories c ON c.id = t.category_id
WHERE t.deleted_at IS NULL;
GRANT SELECT ON public.transactions_with_impact TO authenticated;

CREATE VIEW public.subscription_shock WITH (security_invoker = on) AS
SELECT t.user_id,
       sum(t.amount) AS monthly_recurring_total,
       sum(t.amount) * 12 * p.projection_years * power(1 + p.expected_return, p.projection_years) AS long_term_projection,
       p.projection_years, p.expected_return
FROM public.transactions t
JOIN public.profiles p ON p.id = t.user_id
WHERE t.recurring = true AND t.deleted_at IS NULL
GROUP BY t.user_id, p.projection_years, p.expected_return;
GRANT SELECT ON public.subscription_shock TO authenticated;

CREATE VIEW public.category_monthly_summary WITH (security_invoker = on) AS
SELECT t.user_id, t.category_id, c.name AS category_name,
       date_trunc('month', t.occurred_at)::date AS month,
       sum(t.amount) AS total_amount,
       sum(t.amount) / NULLIF(p.hourly_rate, 0) AS total_hours
FROM public.transactions t
JOIN public.profiles p ON p.id = t.user_id
LEFT JOIN public.categories c ON c.id = t.category_id
WHERE t.deleted_at IS NULL
GROUP BY t.user_id, t.category_id, c.name, date_trunc('month', t.occurred_at), p.hourly_rate;
GRANT SELECT ON public.category_monthly_summary TO authenticated;