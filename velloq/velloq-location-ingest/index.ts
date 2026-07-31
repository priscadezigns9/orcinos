// [Zapia] Velloq location-ingest Edge Function — policy gate, 2026-07-30
// Deploy with Supabase Edge Functions. The service role stays server-side.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const db = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function withinSchedule(now: Date, schedules: any[]) {
  return schedules.some((s) => {
    if (!s.active) return false;
    const parts = new Intl.DateTimeFormat("en-US", { timeZone: s.timezone || "America/Port_of_Spain", weekday: "short", hour: "2-digit", minute: "2-digit", hour12: false }).formatToParts(now);
    const weekday = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].indexOf(parts.find((p) => p.type === "weekday")?.value || "");
    const hour = Number(parts.find((p) => p.type === "hour")?.value || 0);
    const minute = Number(parts.find((p) => p.type === "minute")?.value || 0);
    if (Number(s.day_of_week) !== weekday) return false;
    const [sh, sm] = String(s.starts_at).slice(0, 5).split(":").map(Number);
    const [eh, em] = String(s.ends_at).slice(0, 5).split(":").map(Number);
    return hour * 60 + minute >= sh * 60 + sm && hour * 60 + minute <= eh * 60 + em;
  });
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST required" }, 405);
  const body = await req.json().catch(() => null);
  const { link_identifier, latitude, longitude, accuracy_m, recorded_at } = body ?? {};
  if (!link_identifier || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
    return json({ error: "link_identifier, latitude and longitude are required" }, 400);
  }

  const { data: person } = await db.from("v_personnel").select("id,tenant_id,status").eq("link_identifier", link_identifier).maybeSingle();
  if (!person || person.status !== "active") return json({ status: "revoked_or_unknown" }, 403);

  const { data: consent } = await db.from("v_location_consents").select("granted").eq("personnel_id", person.id).maybeSingle();
  const { data: schedules } = await db.from("v_work_schedules").select("day_of_week,starts_at,ends_at,timezone,active").eq("personnel_id", person.id);
  const { data: assignments } = await db.from("v_personnel_assignments").select("worksite_id,v_worksites(latitude,longitude,radius_m,active)").eq("personnel_id", person.id);

  const now = recorded_at ? new Date(recorded_at) : new Date();
  const scheduled = withinSchedule(now, schedules ?? []);
  const sites = (assignments ?? []).map((a: any) => a.v_worksites).filter((s: any) => s?.active);
  const inGeofence = sites.some((s: any) => vDistance(latitude, longitude, s.latitude, s.longitude) <= s.radius_m);
  const accepted = Boolean(consent?.granted && scheduled && inGeofence);
  const decision = !consent?.granted ? "permission_required" : !scheduled ? "outside_work_hours" : !inGeofence ? "outside_geofence" : "accepted";

  await db.from("v_location_events").insert({ tenant_id: person.tenant_id, personnel_id: person.id, latitude, longitude, accuracy_m, recorded_at: now.toISOString(), accepted, decision });
  await db.from("v_privacy_audit_log").insert({ tenant_id: person.tenant_id, personnel_id: person.id, event_type: "location_decision", detail: { decision, scheduled, in_geofence: inGeofence, consent: Boolean(consent?.granted) } });

  if (accepted) {
    await db.from("v_personnel_latest_location").upsert({ personnel_id: person.id, tenant_id: person.tenant_id, latitude, longitude, accuracy_m, status: "active", last_seen_at: now.toISOString(), updated_at: new Date().toISOString() });
  } else {
    await db.from("v_personnel_latest_location").upsert({ personnel_id: person.id, tenant_id: person.tenant_id, latitude: null, longitude: null, accuracy_m: null, status: decision, last_seen_at: null, updated_at: new Date().toISOString() });
  }
  return json({ status: decision, location_transmitted: accepted });
});

function vDistance(a: number, b: number, c: number, d: number) {
  const r = Math.PI / 180, x = (c - a) * r, y = (d - b) * r;
  const q = Math.sin(x / 2) ** 2 + Math.cos(a * r) * Math.cos(c * r) * Math.sin(y / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(q));
}
