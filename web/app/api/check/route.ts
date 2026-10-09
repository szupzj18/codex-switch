import { connection } from "next/server";
import { runCheck } from "@/lib/checks";
import { guard } from "@/lib/guard";
import { readRegistry, ZoruaError } from "@/lib/zorua";

const NAME = /^[A-Za-z0-9_-]{1,32}$/;

/** Check one provider's endpoint and key. Sends the provider's own key to its own endpoint, nowhere else. */
export async function POST(request: Request) {
  await connection();
  const denied = guard(request, true);
  if (denied) return denied;
  let body: { name?: unknown };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid JSON" }, { status: 400 });
  }
  if (typeof body.name !== "string" || !NAME.test(body.name)) {
    return Response.json({ error: "name is missing or invalid" }, { status: 400 });
  }
  try {
    const reg = await readRegistry();
    if (!reg.providers.some((p) => p.name === body.name)) {
      return Response.json({ error: `unknown provider '${body.name}'` }, { status: 400 });
    }
    return Response.json({ check: await runCheck(body.name) }, { headers: { "Cache-Control": "no-store" } });
  } catch (e) {
    if (e instanceof ZoruaError) return Response.json({ error: e.message }, { status: 422 });
    return Response.json({ error: "internal error" }, { status: 500 });
  }
}
