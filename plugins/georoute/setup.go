package georoute

import (
	"fmt"

	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/plugin"
	clog "github.com/coredns/coredns/plugin/pkg/log"
)

func init() { plugin.Register("georoute", setup) }

func setup(c *caddy.Controller) error {
	clog.Info("[georoute] setup called")
	georoute := &GeoRoute{}

	for c.Next() {
		for c.NextBlock() {
			switch c.Val() {
			case "geoip_db":
				if !c.NextArg() {
					return c.ArgErr()
				}
				georoute.GeoIPDBPath = c.Val()
			case "cache_size":
				if !c.NextArg() {
					return c.ArgErr()
				}
				var size int
				_, err := fmt.Sscanf(c.Val(), "%d", &size)
				if err != nil || size <= 0 {
					return c.Errf("invalid cache_size value: %s", c.Val())
				}
				georoute.CacheSize = size
			case "distance_threshold":
				if !c.NextArg() {
					return c.ArgErr()
				}
				var threshold float64
				_, err := fmt.Sscanf(c.Val(), "%f", &threshold)
				if err != nil || threshold <= 0 {
					return c.Errf("invalid distance_threshold value: %s", c.Val())
				}
				georoute.DistanceThreshold = threshold
			}
		}
	}

	georoute.InitGeoRoute()
	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		georoute.Next = next
		return georoute
	})
	return nil
}
