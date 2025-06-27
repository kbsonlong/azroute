package azroute

import (
	"log"

	"github.com/coredns/caddy"
	"github.com/coredns/coredns/core/dnsserver"
	"github.com/coredns/coredns/plugin"
	clog "github.com/coredns/coredns/plugin/pkg/log"
)

func init() { plugin.Register("azroute", setup) }

func setup(c *caddy.Controller) error {
	clog.Info("[azroute] setup called")
	log.Printf("[azroute] setup called")
	azroute := &AzRoute{}

	for c.Next() {
		for c.NextBlock() {
			switch c.Val() {
			case "azmap_api":
				if !c.NextArg() {
					return c.ArgErr()
				}
				azroute.ApiUrl = c.Val()
			}
		}
	}

	azroute.InitAndUpdateAzMap()
	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		azroute.Next = next
		return azroute
	})
	return nil
}
