import { connection } from "next/server";
import { BadRequest, perform } from "@/lib/actions";
import { guard } from "@/lib/guard";
import { ZoruaError } from "@/lib/zorua";

export async function POST(request: Request) {
  await connection();
  const denied = guard(request, true);
  if (denied) return denied;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "invalid JSON" }, { status: 400 });
  }
  try {
    return Response.json(await perform(body), { headers: { "Cache-Control": "no-store" } });
  } catch (e) {
    if (e instanceof BadRequest) return Response.json({ error: e.message }, { status: 400 });
    if (e instanceof ZoruaError) return Response.json({ error: e.message }, { status: 422 });
    return Response.json({ error: "internal error" }, { status: 500 });
  }
}
