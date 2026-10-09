import { connection } from "next/server";
import { guard } from "@/lib/guard";
import { getState } from "@/lib/zorua";

export async function GET(request: Request) {
  await connection();
  const denied = guard(request, false);
  if (denied) return denied;
  const force = new URL(request.url).searchParams.has("refresh");
  try {
    const body = await getState(force);
    return Response.json(body, { headers: { "Cache-Control": "no-store" } });
  } catch (e) {
    return Response.json(
      { error: e instanceof Error ? e.message : String(e) },
      { status: 502, headers: { "Cache-Control": "no-store" } },
    );
  }
}
