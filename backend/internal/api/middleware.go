package api

import (
	"database/sql"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/syncer"
)

// Server 聚合 API 处理所需的依赖。
type Server struct {
	DB        *sql.DB
	Cfg       *config.Config
	Hub       *syncer.Hub
	Scheduler *syncer.Scheduler
}

// CORSMiddleware 允许客户端跨域及携带认证头请求。
func CORSMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Origin, Content-Type, Authorization, Accept")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}

// AuthMiddleware 校验 Bearer Token 或 URL query token。
func (s *Server) AuthMiddleware() gin.HandlerFunc {
	return func(c *gin.Context) {
		var token string
		authHeader := c.GetHeader("Authorization")
		if strings.HasPrefix(strings.ToLower(authHeader), "bearer ") {
			token = strings.TrimSpace(authHeader[7:])
		}
		if token == "" {
			token = strings.TrimSpace(c.Query("token"))
		}
		if token == "" {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "未提供认证令牌"})
			return
		}
		claims, err := crypto.ParseToken(token, s.Cfg.JWTSecret)
		if err != nil {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "认证令牌无效或已过期"})
			return
		}
		c.Set("user_id", claims.UserID)
		c.Set("username", claims.Username)
		c.Next()
	}
}

func currentUserID(c *gin.Context) int64 {
	v, _ := c.Get("user_id")
	id, _ := v.(int64)
	return id
}
