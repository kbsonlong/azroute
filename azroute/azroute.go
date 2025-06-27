package azroute

import (
	context "context"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coredns/coredns/plugin"
	"github.com/miekg/dns"
)

type AzMapEntry struct {
	Subnet string `json:"sub"`
	AZ     string `json:"az"`
}

type AzRoute struct {
	Next      plugin.Handler
	AzMap     []AzMapEntry
	AzMapLock sync.RWMutex
	ApiUrl    string
	IpAzMap   map[string]string // IP -> AZ
}

type responseCaptureWriter struct {
	dns.ResponseWriter
	Msg *dns.Msg
}

func (r *responseCaptureWriter) WriteMsg(res *dns.Msg) error {
	r.Msg = res
	return nil // 不直接写出，由 azroute 处理
}

func (a *AzRoute) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
	// 捕获下游（如 hosts）插件的响应
	rw := &responseCaptureWriter{ResponseWriter: w}
	code, err := plugin.NextOrFailure(a.Name(), a.Next, ctx, rw, r)
	if err != nil || rw.Msg == nil || len(rw.Msg.Answer) == 0 {
		return code, err
	}
	// 仅有一个地址时没有必要判断可用区逻辑直接返回
	if len(rw.Msg.Answer) == 1 {
		w.WriteMsg(rw.Msg)
		return dns.RcodeSuccess, nil
	}

	clientIP := getClientIP(w.RemoteAddr().String())
	az := a.findAZ(clientIP)
	log.Printf("[azroute] clientIP=%s, matched AZ=%s", clientIP, az)

	var answers []dns.RR
	var allAnswers []dns.RR
	var allIPs []string
	for _, rr := range rw.Msg.Answer {
		switch v := rr.(type) {
		case *dns.A:
			allAnswers = append(allAnswers, rr)
			allIPs = append(allIPs, v.A.String())
			if az != "" && a.findAZ(v.A.String()) == az {
				answers = append(answers, rr)
			}
		case *dns.AAAA:
			allAnswers = append(allAnswers, rr)
			allIPs = append(allIPs, v.AAAA.String())
			if az != "" && a.findAZ(v.AAAA.String()) == az {
				answers = append(answers, rr)
			}
		default:
			// 其他类型直接透传
		}
	}
	log.Printf("[azroute] hosts returned IPs: %v", allIPs)
	// 如果没有同 AZ 的，返回全部 A/AAAA
	if len(answers) == 0 || len(allIPs) == 1 {
		answers = allAnswers
	}
	var retIPs []string
	for _, rr := range answers {
		switch v := rr.(type) {
		case *dns.A:
			retIPs = append(retIPs, v.A.String())
		case *dns.AAAA:
			retIPs = append(retIPs, v.AAAA.String())
		}
	}
	log.Printf("[azroute] final returned IPs: %v", retIPs)
	if len(answers) == 0 {
		return code, err
	}

	m := new(dns.Msg)
	m.SetReply(r)
	m.Answer = answers
	w.WriteMsg(m)
	return dns.RcodeSuccess, nil
}

func getClientIP(addr string) string {
	if strings.Contains(addr, "[") { // IPv6
		addr = strings.Split(addr, "]:")[0]
		addr = strings.TrimPrefix(addr, "[")
	} else {
		addr = strings.Split(addr, ":")[0]
	}
	return addr
}

func (a *AzRoute) findAZ(ip string) string {
	a.AzMapLock.RLock()
	defer a.AzMapLock.RUnlock()
	ipAddr := net.ParseIP(ip)
	for _, entry := range a.AzMap {
		_, subnet, err := net.ParseCIDR(entry.Subnet)
		if err == nil {
			log.Printf("[azroute] findAZ: check ip=%s in subnet=%s", ip, entry.Subnet)
			if subnet.Contains(ipAddr) {
				log.Printf("[azroute] findAZ: ip=%s matched subnet=%s, az=%s", ip, entry.Subnet, entry.AZ)
				return entry.AZ
			}
		}
	}
	return ""
}

func (a *AzRoute) Name() string { return "azroute" }

func (a *AzRoute) InitAndUpdateAzMap() {
	a.fetchAzMap()
	go func() {
		for {
			time.Sleep(60 * time.Second)
			a.fetchAzMap()
		}
	}()
}

func (a *AzRoute) fetchAzMap() {
	resp, err := http.Get(a.ApiUrl)
	if err != nil {
		log.Printf("[azroute] fetch API error: %v", err)
		return
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[azroute] read API body error: %v", err)
		return
	}
	var azmap []AzMapEntry
	if err := json.Unmarshal(body, &azmap); err != nil {
		log.Printf("[azroute] unmarshal API json error: %v", err)
		return
	}
	a.AzMapLock.Lock()
	a.AzMap = azmap
	a.AzMapLock.Unlock()
	log.Printf("[azroute] API数据已热加载")
}
