// _worker.js
export default {
  async fetch(request, env, ctx) {
    const S = env.S;

    const url = new URL(request.url);

    const commonHeaders = {
      "X-Robots-Tag": "noindex, nofollow",
      "content-type": "text/plain; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": "no-store, no-cache, must-revalidate, proxy-revalidate",
      Pragma: "no-cache",
      Expires: "0",
    };

    if (!S) {
      return new Response(
        "Server Config Error: 'S' environment variable is not set in Cloudflare Dashboard.",
        {
          status: 500,
          headers: commonHeaders,
        },
      );
    }

    const userKey = url.searchParams.get("key");
    if (userKey !== S) {
      return new Response(
        "Access Denied: Invalid or missing 'key' parameter.",
        {
          status: 403,
          headers: commonHeaders,
        },
      );
    }

    let targetUrlStr = url.searchParams.get("url");
    if (!targetUrlStr) {
      const rawQuery = request.url.split("?")[1];
      if (rawQuery && rawQuery.includes("url=")) {
        targetUrlStr = decodeURIComponent(
          rawQuery.substring(rawQuery.indexOf("url=") + 4),
        );
      }
    }

    if (!targetUrlStr) {
      return new Response("Converter is Running. 🔒", {
        headers: commonHeaders,
      });
    }

    try {
      const targetUrl = new URL(targetUrlStr);

      const response = await fetch(targetUrl.toString(), {
        headers: {
          "User-Agent": "clash-verge/v2.5.2",
        },
      });

      if (!response.ok) throw new Error(`Upstream Error: ${response.status}`);

      const text = await response.text();

      if (isBase64OrList(text)) {
        return new Response(text, {
          headers: {
            ...commonHeaders,
            "profile-update-interval": "24",
            "subscription-userinfo":
              response.headers.get("subscription-userinfo") || "",
          },
        });
      }

      const v2rayLinks = parseYamlToV2ray(text);

      if (v2rayLinks.length === 0) {
        return new Response(
          "Failed to parse nodes.\nPreview:\n" + text.substring(0, 500),
          { status: 500, headers: commonHeaders },
        );
      }

      const finalString = v2rayLinks.join("\n");
      const base64String = btoa(unescape(encodeURIComponent(finalString)));

      return new Response(base64String, {
        headers: {
          ...commonHeaders,
          "subscription-userinfo":
            response.headers.get("subscription-userinfo") || "",
        },
      });
    } catch (e) {
      return new Response(`Server Error: ${e.message}`, {
        status: 500,
        headers: commonHeaders,
      });
    }
  },
};

function isBase64OrList(str) {
  if (str.includes("proxies:") || str.includes("proxy-groups:")) return false;
  if (
    str.includes("hysteria2://") ||
    str.includes("vless://") ||
    str.includes("vmess://") ||
    str.includes("trojan://") ||
    str.includes("ss://")
  )
    return true;
  if (!str.includes(":")) return true;
  return false;
}

function parseYamlToV2ray(yamlText) {
  let links = [];
  const blocks = yamlText.split(/-\s+name:/);

  for (let i = 0; i < blocks.length; i++) {
    let block = blocks[i];
    const typeMatch = block.match(/type:\s*([a-zA-Z0-9]+)/);
    if (!typeMatch) continue;
    const type = typeMatch[1].toLowerCase();

    const server = block.match(/server:\s*([^\s\n]+)/)?.[1];
    const port = block.match(/port:\s*(\d+)/)?.[1];
    const password = block.match(/(password|uuid):\s*([^\s\n]+)/)?.[2];
    const sni = block.match(/(sni|servername):\s*([^\s\n]+)/)?.[2];
    const network = block.match(/network:\s*([^\s\n]+)/)?.[1] || "tcp";
    const skipCert = block.match(/skip-cert-verify:\s*(true|false)/)?.[1];

    let ps = `${type.toUpperCase()}-${server}`;

    if (type === "hysteria2") {
      if (server && port && password) {
        let link = `hysteria2://${password}@${server}:${port}?`;
        if (sni) link += `&sni=${sni}`;
        if (skipCert === "true") link += `&insecure=1`;
        link += `#${encodeURIComponent(ps)}`;
        links.push(link);
      }
    } else if (type === "vless") {
      if (server && port && password) {
        let link = `vless://${password}@${server}:${port}?encryption=none&security=tls&type=${network}`;
        if (sni) link += `&sni=${sni}`;
        if (block.includes("flow:"))
          link += `&flow=${block.match(/flow:\s*([^\s\n]+)/)?.[1]}`;
        const pbk = block.match(/public-key:\s*([^\s\n]+)/)?.[1];
        if (pbk) link += `&fp=chrome&pbk=${pbk}&security=reality`;
        link += `#${encodeURIComponent(ps)}`;
        links.push(link);
      }
    } else if (type === "trojan") {
      if (server && port && password) {
        let link = `trojan://${password}@${server}:${port}?security=tls`;
        if (sni) link += `&sni=${sni}`;
        if (skipCert === "true") link += `&allowInsecure=1`;
        link += `#${encodeURIComponent(ps)}`;
        links.push(link);
      }
    } else if (type === "vmess") {
      if (server && port && password) {
        const vmessObj = {
          v: "2",
          ps: ps,
          add: server,
          port: port,
          id: password,
          aid: block.match(/alterId:\s*(\d+)/)?.[1] || "0",
          scy: block.match(/cipher:\s*([^\s\n]+)/)?.[1] || "auto",
          net: network,
          type: "none",
          host:
            block.match(/ws-headers:.*?Host:\s*([^\s\n]+)/s)?.[1] || sni || "",
          path: block.match(/ws-path:\s*([^\s\n]+)/)?.[1] || "/",
          tls: block.match(/tls:\s*(true|false)/)?.[1] === "true" ? "tls" : "",
        };
        links.push(`vmess://${btoa(JSON.stringify(vmessObj))}`);
      }
    } else if (type === "ss") {
      const cipher = block.match(/cipher:\s*([^\s\n]+)/)?.[1];
      if (server && port && password && cipher) {
        const auth = btoa(`${cipher}:${password}`);
        let link = `ss://${auth}@${server}:${port}#${encodeURIComponent(ps)}`;
        links.push(link);
      }
    }
  }
  return links;
}
