import { createServerFn } from "@tanstack/react-start";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

export type ProjectionPoint = { year: number; projected_value: number };

/**
 * What-if projection: given a monthly spending reduction, project its future
 * value using the caller's own profile settings. Auth required; only ever
 * reads the caller's profile.
 */
export const whatifProjection = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: { monthly_reduction: number }) => {
    const value = Number(input?.monthly_reduction);
    if (!Number.isFinite(value) || value < 0) {
      throw new Error("monthly_reduction must be a non-negative number");
    }
    return { monthly_reduction: value };
  })
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;

    const { data: profile, error } = await supabase
      .from("profiles")
      .select("hourly_rate, expected_return, projection_years")
      .eq("id", userId)
      .maybeSingle();

    if (error) throw new Error(error.message);
    if (!profile) throw new Error("Profile not found");

    const expectedReturn = Number(profile.expected_return ?? 0.07);
    const projectionYears = Number(profile.projection_years ?? 20);

    const years = [0, 5, 10, 15].filter((y) => y < projectionYears);
    years.push(projectionYears);

    const projection: ProjectionPoint[] = years.map((year) => ({
      year,
      projected_value: data.monthly_reduction * Math.pow(1 + expectedReturn, year),
    }));

    return {
      hourly_rate: Number(profile.hourly_rate ?? 0),
      expected_return: expectedReturn,
      projection_years: projectionYears,
      projection,
    };
  });
