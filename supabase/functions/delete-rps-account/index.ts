import { createClient } from "npm:@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const allowedOrigins = new Set([
  "https://orcinos.com",
  "https://www.orcinos.com",
]);

if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("Required Supabase server configuration is missing.");
}

function responseHeaders(origin: string) {
  return {
    "Access-Control-Allow-Origin": allowedOrigins.has(origin) ? origin : "https://orcinos.com",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
    "Content-Type": "application/json; charset=utf-8",
  };
}

function jsonResponse(origin: string, status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(origin),
  });
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin") ?? "";
  const headers = responseHeaders(origin);

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers });
  }
  if (origin && !allowedOrigins.has(origin)) {
    return jsonResponse(origin, 403, { error: "This request is not allowed." });
  }
  if (request.method !== "POST") {
    return jsonResponse(origin, 405, { error: "Method not allowed." });
  }

  const authorization = request.headers.get("authorization") ?? "";
  const tokenMatch = authorization.match(/^Bearer\s+(.+)$/i);
  if (!tokenMatch) {
    return jsonResponse(origin, 401, { error: "Please sign in again to continue." });
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
      detectSessionInUrl: false,
    },
  });

  // Validate the caller's access token with Supabase Auth; never accept a user ID from the request.
  const { data: authData, error: authError } = await admin.auth.getUser(tokenMatch[1]);
  if (authError || !authData.user) {
    return jsonResponse(origin, 401, { error: "Your sign-in has expired. Please sign in again." });
  }

  // The RPC is executable only by service_role and deletes data for this verified user ID.
  const { error: purgeError } = await admin.rpc("rps_v2_admin_delete_account_data", {
    p_user_id: authData.user.id,
  });
  if (purgeError) {
    console.error("RPS account data cleanup failed.");
    return jsonResponse(origin, 500, { error: "Account deletion could not be completed. Please try again." });
  }

  const { error: deleteError } = await admin.auth.admin.deleteUser(authData.user.id);
  if (deleteError) {
    console.error("Supabase Auth account deletion failed.");
    return jsonResponse(origin, 500, { error: "Account deletion could not be completed. Please try again." });
  }

  return jsonResponse(origin, 200, { ok: true });
});
