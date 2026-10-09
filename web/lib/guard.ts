const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1", "[::1]"]);

/**
 * Local-only guard. Reads need a loopback Host (DNS rebinding). Writes also need the same
 * Origin, a JSON body and a custom header, none of which a cross-site page can send.
 */
export function guard(request: Request, write: boolean): Response | null {
  const host = request.headers.get("host") ?? "";
  let hostname = "";
  try {
    hostname = new URL(`http://${host}`).hostname;
  } catch {}
  if (!LOCAL_HOSTS.has(hostname)) return Response.json({ error: "forbidden host" }, { status: 403 });
  if (!write) return null;
  if (request.headers.get("origin") !== `http://${host}`) {
    return Response.json({ error: "forbidden origin" }, { status: 403 });
  }
  if (!(request.headers.get("content-type") ?? "").startsWith("application/json")) {
    return Response.json({ error: "expected application/json" }, { status: 415 });
  }
  if (request.headers.get("x-zorua-web") !== "1") {
    return Response.json({ error: "missing x-zorua-web header" }, { status: 403 });
  }
  return null;
}
