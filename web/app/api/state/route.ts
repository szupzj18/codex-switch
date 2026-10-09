import { connection } from "next/server";
import { getState } from "@/lib/zorua";

const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

export async function GET(request: Request) {
  await connection();
  // Refuse requests whose Host is not loopback (DNS rebinding).
  const host = request.headers.get("host") ?? "";
  let hostname = "";
  try {
    hostname = new URL(`http://${host}`).hostname;
  } catch {}
  if (!LOCAL_HOSTS.has(hostname)) {
    return Response.json({ error: "forbidden host" }, { status: 403 });
  }
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
