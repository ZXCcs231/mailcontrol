package api

import (
	_ "embed"
	"net/http"

	"github.com/gin-gonic/gin"
)

//go:embed admin_ui.html
var adminUIHTML string

// AdminPage 返回内嵌的 /admin 服务端管理控制台 HTML 页面。
func (s *Server) AdminPage(c *gin.Context) {
	c.Data(http.StatusOK, "text/html; charset=utf-8", []byte(adminUIHTML))
}
