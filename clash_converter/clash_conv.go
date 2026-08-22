package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strings"
)

var (
	// 各字段匹配用的正则，语义与原 JS 版本一致
	reBlockSep = regexp.MustCompile(`-\s+name:`)
	reType     = regexp.MustCompile(`type:\s*([a-zA-Z0-9]+)`)
	reServer   = regexp.MustCompile(`server:\s*([^\s\n]+)`)
	rePort     = regexp.MustCompile(`port:\s*(\d+)`)
	rePassword = regexp.MustCompile(`(password|uuid):\s*([^\s\n]+)`)
	reSNI      = regexp.MustCompile(`(sni|servername):\s*([^\s\n]+)`)
	reNetwork  = regexp.MustCompile(`network:\s*([^\s\n]+)`)
	reSkipCert = regexp.MustCompile(`skip-cert-verify:\s*(true|false)`)
	reFlow     = regexp.MustCompile(`flow:\s*([^\s\n]+)`)
	rePubKey   = regexp.MustCompile(`public-key:\s*([^\s\n]+)`)
	reAlterID  = regexp.MustCompile(`alterId:\s*(\d+)`)
	reCipher   = regexp.MustCompile(`cipher:\s*([^\s\n]+)`)
	reWSHost   = regexp.MustCompile(`(?s)ws-headers:.*?Host:\s*([^\s\n]+)`)
	reWSPath   = regexp.MustCompile(`ws-path:\s*([^\s\n]+)`)
	reTLS      = regexp.MustCompile(`tls:\s*(true|false)`)
)

func main() {
	addr := getenv("ADDR", ":2080")
	http.HandleFunc("/", handler)
	log.Printf("订阅转换器启动，监听 %s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func handler(w http.ResponseWriter, r *http.Request) {
	commonHeaders(w)

	targetURLStr := r.URL.Query().Get("url")
	if targetURLStr == "" {
		// 兜底：从原始查询串里取 url= 之后的部分
		raw := r.URL.RawQuery
		if _, after, found := strings.Cut(raw, "url="); found {
			if decoded, err := url.QueryUnescape(after); err == nil {
				targetURLStr = decoded
			}
		}
	}
	if targetURLStr == "" {
		fmt.Fprint(w, "转换器运行中。🔒")
		return
	}

	target, err := url.Parse(targetURLStr)
	if err != nil {
		httpError(w, http.StatusInternalServerError, "目标地址无效："+err.Error())
		return
	}

	req, err := http.NewRequest(http.MethodGet, target.String(), nil)
	if err != nil {
		httpError(w, http.StatusInternalServerError, "请求构造失败："+err.Error())
		return
	}
	req.Header.Set("User-Agent", "clash-verge/v2.5.2")

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		httpError(w, http.StatusInternalServerError, "上游请求失败："+err.Error())
		return
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		httpError(w, http.StatusInternalServerError, fmt.Sprintf("上游错误：%d", resp.StatusCode))
		return
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		httpError(w, http.StatusInternalServerError, "读取上游响应失败："+err.Error())
		return
	}
	text := string(body)

	subscriptionInfo := resp.Header.Get("subscription-userinfo")

	if isBase64OrList(text) {
		w.Header().Set("profile-update-interval", "24")
		w.Header().Set("subscription-userinfo", subscriptionInfo)
		io.WriteString(w, text)
		return
	}

	links := parseYamlToV2ray(text)
	if len(links) == 0 {
		preview := text
		if len(preview) > 500 {
			preview = preview[:500]
		}
		httpError(w, http.StatusInternalServerError, "解析节点失败。\n预览：\n"+preview)
		return
	}

	final := strings.Join(links, "\n")
	encoded := base64.StdEncoding.EncodeToString([]byte(final))

	w.Header().Set("subscription-userinfo", subscriptionInfo)
	io.WriteString(w, encoded)
}

func commonHeaders(w http.ResponseWriter) {
	h := w.Header()
	h.Set("X-Robots-Tag", "noindex, nofollow")
	h.Set("Content-Type", "text/plain; charset=utf-8")
	h.Set("Access-Control-Allow-Origin", "*")
	h.Set("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate")
	h.Set("Pragma", "no-cache")
	h.Set("Expires", "0")
}

func httpError(w http.ResponseWriter, code int, msg string) {
	w.WriteHeader(code)
	io.WriteString(w, msg)
}

func isBase64OrList(s string) bool {
	if strings.Contains(s, "proxies:") || strings.Contains(s, "proxy-groups:") {
		return false
	}
	if strings.Contains(s, "hysteria2://") ||
		strings.Contains(s, "vless://") ||
		strings.Contains(s, "vmess://") ||
		strings.Contains(s, "trojan://") ||
		strings.Contains(s, "ss://") ||
		strings.Contains(s, "anytls://") {
		return true
	}
	if !strings.Contains(s, ":") {
		return true
	}
	return false
}

func parseYamlToV2ray(yamlText string) []string {
	var links []string
	blocks := reBlockSep.Split(yamlText, -1)

	for _, block := range blocks {
		typeMatch := reType.FindStringSubmatch(block)
		if typeMatch == nil {
			continue
		}
		typ := strings.ToLower(typeMatch[1])

		server := firstSubmatch(reServer, block)
		port := firstSubmatch(rePort, block)
		password := secondSubmatch(rePassword, block)

		sni := secondSubmatch(reSNI, block)

		network := firstSubmatch(reNetwork, block)
		if network == "" {
			network = "tcp"
		}
		skipCert := firstSubmatch(reSkipCert, block)

		name := extractName(block)
		ps := name
		if ps == "" {
			ps = strings.ToUpper(typ) + "-" + server
		}

		switch typ {
		case "anytls":
			if server != "" && port != "" && password != "" {
				link := fmt.Sprintf("anytls://%s@%s:%s/", password, server, port)
				var params []string
				if sni != "" {
					params = append(params, "sni="+sni)
				}
				if skipCert == "true" {
					params = append(params, "insecure=1")
				}
				if len(params) > 0 {
					link += "?" + strings.Join(params, "&")
				}
				link += "#" + encodeURIComponent(ps)
				links = append(links, link)
			}
		case "hysteria2":
			if server != "" && port != "" && password != "" {
				link := fmt.Sprintf("hysteria2://%s@%s:%s?", password, server, port)
				if sni != "" {
					link += "&sni=" + sni
				}
				if skipCert == "true" {
					link += "&insecure=1"
				}
				link += "#" + encodeURIComponent(ps)
				links = append(links, link)
			}
		case "vless":
			if server != "" && port != "" && password != "" {
				link := fmt.Sprintf("vless://%s@%s:%s?encryption=none&security=tls&type=%s", password, server, port, network)
				if sni != "" {
					link += "&sni=" + sni
				}
				if strings.Contains(block, "flow:") {
					link += "&flow=" + firstSubmatch(reFlow, block)
				}
				if pbk := firstSubmatch(rePubKey, block); pbk != "" {
					link += "&fp=chrome&pbk=" + pbk + "&security=reality"
				}
				link += "#" + encodeURIComponent(ps)
				links = append(links, link)
			}
		case "trojan":
			if server != "" && port != "" && password != "" {
				link := fmt.Sprintf("trojan://%s@%s:%s?security=tls", password, server, port)
				if sni != "" {
					link += "&sni=" + sni
				}
				if skipCert == "true" {
					link += "&allowInsecure=1"
				}
				link += "#" + encodeURIComponent(ps)
				links = append(links, link)
			}
		case "vmess":
			if server != "" && port != "" && password != "" {
				obj := struct {
					V    string `json:"v"`
					PS   string `json:"ps"`
					Add  string `json:"add"`
					Port string `json:"port"`
					ID   string `json:"id"`
					Aid  string `json:"aid"`
					Scy  string `json:"scy"`
					Net  string `json:"net"`
					Type string `json:"type"`
					Host string `json:"host"`
					Path string `json:"path"`
					TLS  string `json:"tls"`
				}{
					V:    "2",
					PS:   ps,
					Add:  server,
					Port: port,
					ID:   password,
					Aid:  orDefault(firstSubmatch(reAlterID, block), "0"),
					Scy:  orDefault(firstSubmatch(reCipher, block), "auto"),
					Net:  network,
					Type: "none",
					Host: orDefault(firstSubmatch(reWSHost, block), sni),
					Path: orDefault(firstSubmatch(reWSPath, block), "/"),
				}
				if firstSubmatch(reTLS, block) == "true" {
					obj.TLS = "tls"
				}
				jsonBytes, err := json.Marshal(obj)
				if err != nil {
					continue
				}
				links = append(links, "vmess://"+base64.StdEncoding.EncodeToString(jsonBytes))
			}
		case "ss":
			cipher := firstSubmatch(reCipher, block)
			if server != "" && port != "" && password != "" && cipher != "" {
				auth := base64.StdEncoding.EncodeToString([]byte(cipher + ":" + password))
				link := fmt.Sprintf("ss://%s@%s:%s#%s", auth, server, port, encodeURIComponent(ps))
				links = append(links, link)
			}
		}
	}
	return links
}

func extractName(block string) string {
	// block 以 "- name:" 之后的剩余内容开头，首行即节点名（可能带引号）
	if i := strings.IndexByte(block, '\n'); i >= 0 {
		block = block[:i]
	}
	block = strings.TrimSpace(block)
	if len(block) >= 2 {
		if (block[0] == '\'' && block[len(block)-1] == '\'') ||
			(block[0] == '"' && block[len(block)-1] == '"') {
			return block[1 : len(block)-1]
		}
	}
	return block
}

// 等价于 JS 的 encodeURIComponent：空格编码为 %20，而非 url.QueryEscape 的 +
func encodeURIComponent(s string) string {
	const hex = "0123456789ABCDEF"
	var b strings.Builder
	for i := range len(s) {
		c := s[i]
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.' || c == '~' {
			b.WriteByte(c)
		} else {
			b.WriteByte('%')
			b.WriteByte(hex[c>>4])
			b.WriteByte(hex[c&0x0f])
		}
	}
	return b.String()
}

func secondSubmatch(re *regexp.Regexp, s string) string {
	m := re.FindStringSubmatch(s)
	if len(m) < 3 {
		return ""
	}
	return m[2]
}

func firstSubmatch(re *regexp.Regexp, s string) string {
	m := re.FindStringSubmatch(s)
	if len(m) < 2 {
		return ""
	}
	return m[1]
}

func orDefault(v, def string) string {
	if v == "" {
		return def
	}
	return v
}

func getenv(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}
