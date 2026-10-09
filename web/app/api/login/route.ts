import { connection } from "next/server";
import { guard } from "@/lib/guard";
import { getLogin } from "@/lib/jobs";

export async function GET(request: Request) {
  await connection();
  const denied = guard(request, false);
  if (denied) return denied;
  const name = new URL(request.url).searchParams.get("name") ?? "";
  return Response.json({ job: getLogin(name) }, { headers: { "Cache-Control": "no-store" } });
}
