// Go 实现的 HTTP 反向代理 - HTML 内容注入
// 如果你不想用 Nginx/Caddy，可以使用这个独立程序

package main

import (
	"bytes"
	"compress/gzip"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strings"
)

var (
	listenAddr  = flag.String("listen", ":80", "监听地址")
	backendAddr = flag.String("backend", "http://127.0.0.1:8080", "后端服务器地址")
	ownerName   = flag.String("owner", "XXX", "网站所有者名称")
)

// 注入的 HTML 内容
func getInjectedHTML(owner string) string {
	return fmt.Sprintf(`<div style="background:#fffbe6;border-bottom:2px solid #ffe58f;padding:10px;text-align:center;font-size:14px;font-family:sans-serif;position:relative;z-index:99999;">
    <b>此网址属于 %s 拥有</b>
</div>`, owner)
}

// 自定义 ResponseWriter 用于捕获和修改响应
type responseModifier struct {
	http.ResponseWriter
	body        *bytes.Buffer
	statusCode  int
	contentType string
	owner       string
}

func newResponseModifier(w http.ResponseWriter, owner string) *responseModifier {
	return &responseModifier{
		ResponseWriter: w,
		body:           &bytes.Buffer{},
		statusCode:     http.StatusOK,
		owner:          owner,
	}
}

func (rm *responseModifier) WriteHeader(code int) {
	rm.statusCode = code
	rm.contentType = rm.Header().Get("Content-Type")
}

func (rm *responseModifier) Write(b []byte) (int, error) {
	return rm.body.Write(b)
}

func (rm *responseModifier) finalize() {
	body := rm.body.Bytes()

	// 只处理 HTML 内容
	if strings.Contains(rm.contentType, "text/html") {
		body = injectHTML(body, rm.owner)
	}

	// 更新 Content-Length
	rm.Header().Set("Content-Length", fmt.Sprintf("%d", len(body)))
	rm.Header().Del("Content-Encoding") // 移除压缩头

	rm.ResponseWriter.WriteHeader(rm.statusCode)
	rm.ResponseWriter.Write(body)
}

// 正则匹配 <body> 标签
var bodyTagRegex = regexp.MustCompile(`(?i)(<body[^>]*>)`)

func injectHTML(content []byte, owner string) []byte {
	// 尝试解压 gzip 内容
	if isGzipped(content) {
		reader, err := gzip.NewReader(bytes.NewReader(content))
		if err == nil {
			decompressed, err := io.ReadAll(reader)
			reader.Close()
			if err == nil {
				content = decompressed
			}
		}
	}

	html := string(content)
	injectedHTML := getInjectedHTML(owner)

	// 在 <body> 标签后插入内容
	if bodyTagRegex.MatchString(html) {
		html = bodyTagRegex.ReplaceAllString(html, "${1}"+injectedHTML)
	}

	return []byte(html)
}

func isGzipped(data []byte) bool {
	return len(data) >= 2 && data[0] == 0x1f && data[1] == 0x8b
}

func main() {
	flag.Parse()

	backend, err := url.Parse(*backendAddr)
	if err != nil {
		log.Fatalf("无效的后端地址: %v", err)
	}

	proxy := httputil.NewSingleHostReverseProxy(backend)

	// 修改请求，禁用压缩
	originalDirector := proxy.Director
	proxy.Director = func(req *http.Request) {
		originalDirector(req)
		req.Header.Set("Accept-Encoding", "identity")
	}

	// 自定义响应处理
	proxy.ModifyResponse = func(resp *http.Response) error {
		// 检查是否是 HTML
		contentType := resp.Header.Get("Content-Type")
		if !strings.Contains(contentType, "text/html") {
			return nil
		}

		// 读取响应体
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			return err
		}
		resp.Body.Close()

		// 注入 HTML
		modifiedBody := injectHTML(body, *ownerName)

		// 更新响应
		resp.Body = io.NopCloser(bytes.NewReader(modifiedBody))
		resp.ContentLength = int64(len(modifiedBody))
		resp.Header.Set("Content-Length", fmt.Sprintf("%d", len(modifiedBody)))
		resp.Header.Del("Content-Encoding")

		return nil
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		log.Printf("[%s] %s %s", r.RemoteAddr, r.Method, r.URL.Path)
		proxy.ServeHTTP(w, r)
	})

	log.Printf("HTML 注入代理启动")
	log.Printf("监听地址: %s", *listenAddr)
	log.Printf("后端服务: %s", *backendAddr)
	log.Printf("所有者: %s", *ownerName)

	if err := http.ListenAndServe(*listenAddr, nil); err != nil {
		log.Fatalf("服务器启动失败: %v", err)
	}
}
