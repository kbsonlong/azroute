package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type AzMapEntry struct {
	Subnet string `json:"sub"`
	AZ     string `json:"az"`
}

// CIDREntry 内网网段配置项
type CIDREntry struct {
	CIDR string `json:"cidr"`
	Desc string `json:"desc,omitempty"`
}

func main() {
	r := gin.Default()

	// azroute插件API
	r.GET("/azmap", func(c *gin.Context) {
		data := []AzMapEntry{
			{Subnet: "127.0.0.0/24", AZ: "az-01"},
			{Subnet: "10.90.0.0/24", AZ: "az-02"},
		}
		c.JSON(http.StatusOK, data)
	})

	// splitnet插件API
	r.GET("/internal_cidr", func(c *gin.Context) {
		cidrList := []CIDREntry{
			{CIDR: "10.0.0.0/8", Desc: "内网A段"},
			{CIDR: "192.168.0.0/16", Desc: "内网C段"},
			{CIDR: "172.16.0.0/12", Desc: "内网B段"},
			{CIDR: "127.0.0.0/8", Desc: "本地回环"},
		}
		c.JSON(http.StatusOK, cidrList)
	})

	r.Run(":8080")
}
