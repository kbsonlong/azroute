package splitnet

import (
	"context"
	"encoding/json"
	"io"
	"log"
	"net"
	"net/http"
	"sync"
	"time"

	"coredns-plugins/plugins/common"

	"github.com/coredns/coredns/plugin"
	lru "github.com/hashicorp/golang-lru"
	"github.com/miekg/dns"
	"github.com/yl2chen/cidranger"
)

// CIDREntry 内网网段配置项
type CIDREntry struct {
	CIDR string `json:"cidr"`
	Desc string `json:"desc,omitempty"`
}

// SplitNet 内外网区分解析插件
type SplitNet struct {
	Next         plugin.Handler
	ApiUrl       string           // 内网网段API地址
	InternalCIDR []*net.IPNet     // 内网网段列表
	ApiLock      sync.RWMutex     // 读写锁
	ApiInterval  time.Duration    // API刷新间隔
	Ranger       cidranger.Ranger // 高效网段查找结构
	IpCache      *lru.Cache       // IP归属缓存
	CacheSize    int              // 缓存大小
}

// responseCaptureWriter 捕获下游插件响应
type responseCaptureWriter struct {
	dns.ResponseWriter
	Msg *dns.Msg
}

func (r *responseCaptureWriter) WriteMsg(res *dns.Msg) error {
	r.Msg = res
	return nil // 不直接写出，由 splitnet 处理
}

// ServeDNS 处理DNS请求
func (s *SplitNet) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
	// 捕获下游插件的响应
	rw := &responseCaptureWriter{ResponseWriter: w}
	code, err := plugin.NextOrFailure(s.Name(), s.Next, ctx, rw, r)
	if err != nil || rw.Msg == nil || len(rw.Msg.Answer) == 0 {
		return code, err
	}

	// 仅有一个地址时直接返回
	if len(rw.Msg.Answer) == 1 {
		w.WriteMsg(rw.Msg)
		return dns.RcodeSuccess, nil
	}

	clientIP := common.GetClientIP(w.RemoteAddr().String())
	isInternal := s.isInternalIP(clientIP)
	log.Printf("[splitnet] clientIP=%s, isInternal=%v", clientIP, isInternal)

	// 分类所有IP地址
	var allIPs []string
	var internalIPs []string
	var externalIPs []string
	var internalAnswers []dns.RR
	var externalAnswers []dns.RR
	var otherAnswers []dns.RR

	for _, rr := range rw.Msg.Answer {
		switch v := rr.(type) {
		case *dns.A:
			allIPs = append(allIPs, v.A.String())
			if s.isInternalIP(v.A.String()) {
				internalIPs = append(internalIPs, v.A.String())
				internalAnswers = append(internalAnswers, rr)
			} else {
				externalIPs = append(externalIPs, v.A.String())
				externalAnswers = append(externalAnswers, rr)
			}
		case *dns.AAAA:
			allIPs = append(allIPs, v.AAAA.String())
			if s.isInternalIP(v.AAAA.String()) {
				internalIPs = append(internalIPs, v.AAAA.String())
				internalAnswers = append(internalAnswers, rr)
			} else {
				externalIPs = append(externalIPs, v.AAAA.String())
				externalAnswers = append(externalAnswers, rr)
			}
		default:
			// 其他类型直接透传
			otherAnswers = append(otherAnswers, rr)
		}
	}

	log.Printf("[splitnet] hosts returned IPs: %v (internal: %v, external: %v)", allIPs, internalIPs, externalIPs)

	// 智能选择返回策略
	var filteredAnswers []dns.RR

	if isInternal {
		// 内网客户端：优先返回内网IP，如果没有内网IP则返回所有IP
		if len(internalAnswers) > 0 {
			filteredAnswers = append(filteredAnswers, internalAnswers...)
			log.Printf("[splitnet] 内网客户端，返回内网IP: %v", internalIPs)
		} else {
			filteredAnswers = append(filteredAnswers, rw.Msg.Answer...)
			log.Printf("[splitnet] 内网客户端，无内网IP，返回所有IP: %v", allIPs)
		}
	} else {
		// 外网客户端：优先返回外网IP，如果没有外网IP则返回所有IP
		if len(externalAnswers) > 0 {
			filteredAnswers = append(filteredAnswers, externalAnswers...)
			log.Printf("[splitnet] 外网客户端，返回外网IP: %v", externalIPs)
		} else {
			filteredAnswers = append(filteredAnswers, rw.Msg.Answer...)
			log.Printf("[splitnet] 外网客户端，无外网IP，返回所有IP: %v", allIPs)
		}
	}

	// 添加其他类型的记录（如CNAME等）
	filteredAnswers = append(filteredAnswers, otherAnswers...)

	var retIPs []string
	for _, rr := range filteredAnswers {
		switch v := rr.(type) {
		case *dns.A:
			retIPs = append(retIPs, v.A.String())
		case *dns.AAAA:
			retIPs = append(retIPs, v.AAAA.String())
		}
	}
	log.Printf("[splitnet] final returned IPs: %v", retIPs)

	m := new(dns.Msg)
	m.SetReply(r)
	m.Answer = filteredAnswers
	w.WriteMsg(m)
	return dns.RcodeSuccess, nil
}

// isInternalIP 判断是否为内网IP
func (s *SplitNet) isInternalIP(ip string) bool {
	// 先查缓存
	if s.IpCache != nil {
		if v, ok := s.IpCache.Get(ip); ok {
			return v.(bool)
		}
	}

	s.ApiLock.RLock()
	defer s.ApiLock.RUnlock()

	if s.Ranger == nil {
		return false
	}

	ipAddr := net.ParseIP(ip)
	entries, err := s.Ranger.ContainingNetworks(ipAddr)
	if err != nil || len(entries) == 0 {
		// 缓存结果
		if s.IpCache != nil {
			s.IpCache.Add(ip, false)
		}
		return false
	}

	// 缓存结果
	if s.IpCache != nil {
		s.IpCache.Add(ip, true)
	}
	return true
}

// Name 插件名称
func (s *SplitNet) Name() string { return "splitnet" }

// InitAndUpdateCIDR 初始化并定期更新内网网段
func (s *SplitNet) InitAndUpdateCIDR() {
	s.fetchCIDR()

	// 初始化LRU缓存
	cacheSize := s.CacheSize
	if cacheSize <= 0 {
		cacheSize = 1024 // 默认值
	}
	cache, err := lru.New(cacheSize)
	if err != nil {
		log.Printf("[splitnet] LRU缓存初始化失败: %v", err)
	} else {
		s.IpCache = cache
	}

	go func() {
		for {
			time.Sleep(s.ApiInterval)
			s.fetchCIDR()
		}
	}()
}

// fetchCIDR 从API获取内网网段
func (s *SplitNet) fetchCIDR() {
	resp, err := http.Get(s.ApiUrl)
	if err != nil {
		log.Printf("[splitnet] fetch API error: %v", err)
		return
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("[splitnet] read API body error: %v", err)
		return
	}

	var cidrList []CIDREntry
	if err := json.Unmarshal(body, &cidrList); err != nil {
		log.Printf("[splitnet] unmarshal API json error: %v", err)
		return
	}

	s.ApiLock.Lock()
	// 构建Ranger
	ranger := cidranger.NewPCTrieRanger()
	for _, entry := range cidrList {
		_, network, err := net.ParseCIDR(entry.CIDR)
		if err == nil {
			ranger.Insert(&cidrRangerEntry{network: *network, desc: entry.Desc})
		}
	}
	s.Ranger = ranger
	s.InternalCIDR = nil
	for _, entry := range cidrList {
		_, network, err := net.ParseCIDR(entry.CIDR)
		if err == nil {
			s.InternalCIDR = append(s.InternalCIDR, network)
		}
	}
	// 清空缓存
	if s.IpCache != nil {
		s.IpCache.Purge()
	}
	s.ApiLock.Unlock()
	log.Printf("[splitnet] 内网网段已热加载，共 %d 个网段", len(s.InternalCIDR))
}

// cidrRangerEntry 实现cidranger.RangerEntry接口
type cidrRangerEntry struct {
	network net.IPNet
	desc    string
}

func (e *cidrRangerEntry) Network() net.IPNet {
	return e.network
}

func (e *cidrRangerEntry) Desc() string {
	return e.desc
}
