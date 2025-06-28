package geoip

import (
	"strconv"

	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/plugin"
)

func init() { plugin.Register("geoip", setup) }

func setup(c *caddy.Controller) error {
	g := &GeoIP{
		CacheSize:         1024, // 默认缓存大小
		DistanceThreshold: 1000, // 默认距离阈值1000公里
	}

	for c.Next() {
		for c.NextBlock() {
			switch c.Val() {
			case "geoip_db":
				if !c.NextArg() {
					return plugin.Error("geoip", c.ArgErr())
				}
				g.GeoIPDBPath = c.Val()
			case "cache_size":
				if !c.NextArg() {
					return plugin.Error("geoip", c.ArgErr())
				}
				size, err := strconv.Atoi(c.Val())
				if err != nil {
					return plugin.Error("geoip", err)
				}
				g.CacheSize = size
			case "distance_threshold":
				if !c.NextArg() {
					return plugin.Error("geoip", c.ArgErr())
				}
				threshold, err := strconv.ParseFloat(c.Val(), 64)
				if err != nil {
					return plugin.Error("geoip", err)
				}
				g.DistanceThreshold = threshold
			default:
				return plugin.Error("geoip", c.Errf("unknown property '%s'", c.Val()))
			}
		}
	}

	// 初始化插件
	g.InitGeoIP()

	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		g.Next = next
		return g
	})

	return nil
}
