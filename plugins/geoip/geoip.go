package geoip

import (
	"context"
	"log"
	"math"
	"net"

	"coredns-plugins/plugins/common"

	"github.com/coredns/coredns/plugin"
	lru "github.com/hashicorp/golang-lru"
	"github.com/miekg/dns"
	"github.com/oschwald/geoip2-golang"
)

// GeoLocation 地理位置信息
type GeoLocation struct {
	Country   string  `json:"country"`
	Region    string  `json:"region"`
	City      string  `json:"city"`
	Latitude  float64 `json:"latitude"`
	Longitude float64 `json:"longitude"`
}

// GeoIP 基于GeoIP2的就近解析插件
type GeoIP struct {
	Next              plugin.Handler
	GeoIPDBPath       string         // GeoIP2数据库路径
	GeoIPReader       *geoip2.Reader // GeoIP2数据库读取器
	LocationCache     *lru.Cache     // 地理位置缓存
	CacheSize         int            // 缓存大小
	DistanceThreshold float64        // 距离阈值（公里）
	InternalRanges    []*net.IPNet   // 内网IP范围
}

// responseCaptureWriter 捕获下游插件响应
type responseCaptureWriter struct {
	dns.ResponseWriter
	Msg *dns.Msg
}

func (r *responseCaptureWriter) WriteMsg(res *dns.Msg) error {
	r.Msg = res
	return nil // 不直接写出，由 geoip 处理
}

// ServeDNS 处理DNS请求
func (s *GeoIP) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
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
	clientLocation := s.getClientLocation(clientIP)
	isInternal := common.IsInternalIP(clientIP)

	log.Printf("[geoip] clientIP=%s, isInternal=%v, location=%+v", clientIP, isInternal, clientLocation)

	// 根据地理位置优选解析结果
	var filteredAnswers []dns.RR
	var allIPs []string
	var selectedIPs []string

	for _, rr := range rw.Msg.Answer {
		switch v := rr.(type) {
		case *dns.A:
			allIPs = append(allIPs, v.A.String())
			if s.isPreferredServer(v.A.String(), clientLocation, isInternal) {
				filteredAnswers = append(filteredAnswers, rr)
				selectedIPs = append(selectedIPs, v.A.String())
			}
		case *dns.AAAA:
			allIPs = append(allIPs, v.AAAA.String())
			if s.isPreferredServer(v.AAAA.String(), clientLocation, isInternal) {
				filteredAnswers = append(filteredAnswers, rr)
				selectedIPs = append(selectedIPs, v.AAAA.String())
			}
		default:
			// 其他类型直接透传
			filteredAnswers = append(filteredAnswers, rr)
		}
	}

	log.Printf("[geoip] hosts returned IPs: %v", allIPs)
	log.Printf("[geoip] selected IPs: %v", selectedIPs)

	// 如果没有匹配的结果，返回全部
	if len(filteredAnswers) == 0 {
		filteredAnswers = rw.Msg.Answer
		log.Printf("[geoip] no preferred servers found, returning all IPs")
	}

	var retIPs []string
	for _, rr := range filteredAnswers {
		switch v := rr.(type) {
		case *dns.A:
			retIPs = append(retIPs, v.A.String())
		case *dns.AAAA:
			retIPs = append(retIPs, v.AAAA.String())
		}
	}
	log.Printf("[geoip] final returned IPs: %v", retIPs)

	m := new(dns.Msg)
	m.SetReply(r)
	m.Answer = filteredAnswers
	w.WriteMsg(m)
	return dns.RcodeSuccess, nil
}

// getClientLocation 获取客户端地理位置
func (s *GeoIP) getClientLocation(ip string) *GeoLocation {
	// 先查缓存
	if s.LocationCache != nil {
		if v, ok := s.LocationCache.Get(ip); ok {
			return v.(*GeoLocation)
		}
	}

	if s.GeoIPReader == nil {
		return nil
	}

	ipAddr := net.ParseIP(ip)
	if ipAddr == nil {
		return nil
	}

	// 查询GeoIP2数据库
	record, err := s.GeoIPReader.City(ipAddr)
	if err != nil {
		log.Printf("[geoip] GeoIP lookup failed for %s: %v", ip, err)
		return nil
	}

	location := &GeoLocation{
		Country:   record.Country.Names["en"],
		Region:    "",
		City:      record.City.Names["en"],
		Latitude:  record.Location.Latitude,
		Longitude: record.Location.Longitude,
	}

	// 获取地区信息（如果有的话）
	if len(record.Subdivisions) > 0 {
		location.Region = record.Subdivisions[0].Names["en"]
	}

	// 缓存结果
	if s.LocationCache != nil {
		s.LocationCache.Add(ip, location)
	}

	return location
}

// getServerLocation 获取服务器地理位置
func (s *GeoIP) getServerLocation(serverIP string) *GeoLocation {
	// 先查缓存
	if s.LocationCache != nil {
		cacheKey := "server:" + serverIP
		if v, ok := s.LocationCache.Get(cacheKey); ok {
			return v.(*GeoLocation)
		}
	}

	if s.GeoIPReader == nil {
		return nil
	}

	ipAddr := net.ParseIP(serverIP)
	if ipAddr == nil {
		return nil
	}

	// 查询GeoIP2数据库
	record, err := s.GeoIPReader.City(ipAddr)
	if err != nil {
		log.Printf("[geoip] GeoIP lookup failed for server %s: %v", serverIP, err)
		return nil
	}

	location := &GeoLocation{
		Country:   record.Country.Names["en"],
		Region:    "",
		City:      record.City.Names["en"],
		Latitude:  record.Location.Latitude,
		Longitude: record.Location.Longitude,
	}

	// 获取地区信息（如果有的话）
	if len(record.Subdivisions) > 0 {
		location.Region = record.Subdivisions[0].Names["en"]
	}

	// 缓存结果
	if s.LocationCache != nil {
		cacheKey := "server:" + serverIP
		s.LocationCache.Add(cacheKey, location)
	}

	return location
}

// isPreferredServer 判断是否为优选服务器
func (s *GeoIP) isPreferredServer(serverIP string, clientLocation *GeoLocation, isInternal bool) bool {
	// 如果是内网IP，直接返回（由azroute插件处理可用区调度）
	if isInternal {
		log.Printf("[geoip] client is internal IP, returning server for azroute processing: %s", serverIP)
		return true
	}

	// 如果无法获取客户端位置，返回所有服务器
	if clientLocation == nil {
		log.Printf("[geoip] cannot get client location, returning server: %s", serverIP)
		return true
	}

	// 获取服务器位置信息
	serverLocation := s.getServerLocation(serverIP)
	if serverLocation == nil {
		log.Printf("[geoip] cannot get server location, returning server: %s", serverIP)
		return true
	}

	// 计算距离
	distance := calculateDistance(
		clientLocation.Latitude, clientLocation.Longitude,
		serverLocation.Latitude, serverLocation.Longitude,
	)

	log.Printf("[geoip] server=%s, distance=%.2fkm, threshold=%.2fkm", serverIP, distance, s.DistanceThreshold)

	// 根据距离阈值判断
	if distance <= s.DistanceThreshold {
		log.Printf("[geoip] server %s is within distance threshold", serverIP)
		return true
	}

	log.Printf("[geoip] server %s is too far, distance=%.2fkm", serverIP, distance)
	return false
}

// calculateDistance 计算两点间距离（公里）
func calculateDistance(lat1, lon1, lat2, lon2 float64) float64 {
	const R = 6371 // 地球半径（公里）

	lat1Rad := lat1 * (math.Pi / 180)
	lon1Rad := lon1 * (math.Pi / 180)
	lat2Rad := lat2 * (math.Pi / 180)
	lon2Rad := lon2 * (math.Pi / 180)

	dlat := lat2Rad - lat1Rad
	dlon := lon2Rad - lon1Rad

	a := math.Sin(dlat/2)*math.Sin(dlat/2) + math.Cos(lat1Rad)*math.Cos(lat2Rad)*math.Sin(dlon/2)*math.Sin(dlon/2)
	c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))

	return R * c
}

// Name 插件名称
func (s *GeoIP) Name() string { return "geoip" }

// InitGeoIP 初始化GeoIP插件
func (s *GeoIP) InitGeoIP() {
	// 初始化GeoIP2数据库
	if s.GeoIPDBPath != "" {
		reader, err := geoip2.Open(s.GeoIPDBPath)
		if err != nil {
			log.Printf("[geoip] Failed to open GeoIP database: %v", err)
		} else {
			s.GeoIPReader = reader
			log.Printf("[geoip] GeoIP database loaded: %s", s.GeoIPDBPath)
		}
	}

	// 初始化内网IP范围
	s.InternalRanges = []*net.IPNet{
		{IP: net.ParseIP("10.0.0.0"), Mask: net.CIDRMask(8, 32)},     // 10.0.0.0/8
		{IP: net.ParseIP("172.16.0.0"), Mask: net.CIDRMask(12, 32)},  // 172.16.0.0/12
		{IP: net.ParseIP("192.168.0.0"), Mask: net.CIDRMask(16, 32)}, // 192.168.0.0/16
		{IP: net.ParseIP("127.0.0.0"), Mask: net.CIDRMask(8, 32)},    // 127.0.0.0/8
	}

	// 初始化LRU缓存
	cacheSize := s.CacheSize
	if cacheSize <= 0 {
		cacheSize = 1024 // 默认值
	}
	cache, err := lru.New(cacheSize)
	if err != nil {
		log.Printf("[geoip] LRU缓存初始化失败: %v", err)
	} else {
		s.LocationCache = cache
	}

	// 设置默认距离阈值
	if s.DistanceThreshold <= 0 {
		s.DistanceThreshold = 1000 // 默认1000公里
	}

	log.Printf("[geoip] GeoIP plugin initialized with distance threshold: %.2fkm", s.DistanceThreshold)
}
