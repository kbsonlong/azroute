package splitnet

import (
	"strconv"
	"time"

	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/plugin"
	clog "github.com/coredns/coredns/plugin/pkg/log"
)

func init() { plugin.Register("splitnet", setup) }

func setup(c *caddy.Controller) error {
	clog.Info("[splitnet] setup called")
	splitnet := &SplitNet{}

	for c.Next() {
		for c.NextBlock() {
			switch c.Val() {
			case "cidr_api":
				if !c.NextArg() {
					return c.ArgErr()
				}
				splitnet.ApiUrl = c.Val()
			case "refresh_interval":
				if !c.NextArg() {
					return c.ArgErr()
				}
				duration, err := time.ParseDuration(c.Val())
				if err != nil {
					return c.Errf("invalid refresh_interval value: %s", c.Val())
				}
				splitnet.ApiInterval = duration
			case "cache_size":
				if !c.NextArg() {
					return c.ArgErr()
				}
				size, err := strconv.Atoi(c.Val())
				if err != nil || size <= 0 {
					return c.Errf("invalid cache_size value: %s", c.Val())
				}
				splitnet.CacheSize = size
			}
		}
	}

	// 设置默认值
	if splitnet.ApiInterval == 0 {
		splitnet.ApiInterval = 60 * time.Second
	}

	splitnet.InitAndUpdateCIDR()
	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		splitnet.Next = next
		return splitnet
	})
	return nil
}
