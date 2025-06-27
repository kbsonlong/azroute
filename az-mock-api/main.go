package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type AzMapEntry struct {
	Subnet string `json:"sub"`
	AZ     string `json:"az"`
}

func main() {
	r := gin.Default()
	r.GET("/azmap", func(c *gin.Context) {
		data := []AzMapEntry{
			{Subnet: "127.0.0.0/24", AZ: "az-01"},
			{Subnet: "10.90.0.0/24", AZ: "az-02"},
		}
		c.JSON(http.StatusOK, data)
	})
	r.Run(":8080")
}
