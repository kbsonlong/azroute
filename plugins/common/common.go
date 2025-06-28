package common

import (
	"net"
	"strings"
)

// GetClientIP 提取客户端IP
func GetClientIP(addr string) string {
	if strings.Contains(addr, "[") { // IPv6
		addr = strings.Split(addr, "]:")[0]
		addr = strings.TrimPrefix(addr, "[")
	} else {
		addr = strings.Split(addr, ":")[0]
	}
	return addr
}

// IsInternalIP 判断是否为内网IP（静态通用版，适合无网段动态配置场景）
func IsInternalIP(ip string) bool {
	ipAddr := net.ParseIP(ip)
	if ipAddr == nil {
		return false
	}
	// IPv4
	if ip4 := ipAddr.To4(); ip4 != nil {
		switch {
		case ip4[0] == 10:
			return true
		case ip4[0] == 172 && ip4[1] >= 16 && ip4[1] <= 31:
			return true
		case ip4[0] == 192 && ip4[1] == 168:
			return true
		case ip4[0] == 127:
			return true
		}
	}
	// IPv6
	if ipAddr.IsLoopback() || ipAddr.IsLinkLocalUnicast() || ipAddr.IsLinkLocalMulticast() {
		return true
	}
	return false
}
