package api

import (
	"database/sql"
	"fmt"
	"net"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/crypto"
	"mailcontrol-backend/internal/models"
	"mailcontrol-backend/internal/rules"
)

type registerReq struct {
	Username string `json:"username" binding:"required"`
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
}

type loginReq struct {
	Account  string `json:"account"`
	Username string `json:"username"`
	Password string `json:"password" binding:"required"`
}

func (s *Server) Health(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{
		"status":  "ok",
		"service": "mailcontrol-server",
	})
}

func (s *Server) Register(c *gin.Context) {
	var allowReg string
	if err := s.DB.QueryRow(`SELECT value FROM system_settings WHERE key = 'allow_register'`).Scan(&allowReg); err == nil {
		if strings.EqualFold(allowReg, "false") || allowReg == "0" {
			c.JSON(http.StatusForbidden, gin.H{"error": "管理员已关闭新用户注册，请联系管理员开通账号"})
			return
		}
	}

	var req registerReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请填写完整的用户名、邮箱与密码"})
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.Email = strings.TrimSpace(strings.ToLower(req.Email))
	if len(req.Username) < 2 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "用户名至少需要 2 个字符"})
		return
	}
	if len(req.Password) < 6 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "密码至少需要 6 位"})
		return
	}

	hash, err := crypto.HashPassword(req.Password)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "密码加密失败"})
		return
	}

	var userCount int
	_ = s.DB.QueryRow(`SELECT COUNT(*) FROM users`).Scan(&userCount)
	isAdminInt := 0
	if userCount == 0 {
		isAdminInt = 1
	}

	res, err := s.DB.Exec(
		`INSERT INTO users (username, email, password_hash, is_admin) VALUES (?, ?, ?, ?)`,
		req.Username, req.Email, hash, isAdminInt,
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			c.JSON(http.StatusConflict, gin.H{"error": "用户名或邮箱已被注册"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "注册失败: " + err.Error()})
		return
	}
	uid, _ := res.LastInsertId()
	_, _ = rules.InstallPresetsForUser(s.DB, uid, nil)

	var user models.User
	var admInt, disInt int
	_ = s.DB.QueryRow(`SELECT id, username, email, is_admin, is_disabled, created_at FROM users WHERE id = ?`, uid).
		Scan(&user.ID, &user.Username, &user.Email, &admInt, &disInt, &user.CreatedAt)
	user.IsAdmin = admInt == 1
	user.IsDisabled = disInt == 1

	token, err := crypto.GenerateToken(user.ID, user.Username, s.Cfg.JWTSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "签发令牌失败"})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"token": token,
		"user":  user,
	})
}

func (s *Server) Login(c *gin.Context) {
	var req loginReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入账号与密码"})
		return
	}
	ident := strings.TrimSpace(req.Account)
	if ident == "" {
		ident = strings.TrimSpace(req.Username)
	}
	if ident == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "请输入用户名或邮箱"})
		return
	}

	var user models.User
	var admInt, disInt int
	err := s.DB.QueryRow(`
		SELECT id, username, email, password_hash, is_admin, is_disabled, created_at
		FROM users
		WHERE LOWER(username) = LOWER(?) OR LOWER(email) = LOWER(?)
		LIMIT 1`, ident, ident,
	).Scan(&user.ID, &user.Username, &user.Email, &user.PasswordHash, &admInt, &disInt, &user.CreatedAt)
	if err == sql.ErrNoRows || !crypto.CheckPassword(user.PasswordHash, req.Password) {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "账号或密码错误"})
		return
	}
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "登录查询失败"})
		return
	}
	if disInt == 1 {
		c.JSON(http.StatusForbidden, gin.H{"error": "该账号已被管理员禁用"})
		return
	}
	user.IsAdmin = admInt == 1
	user.IsDisabled = false

	token, err := crypto.GenerateToken(user.ID, user.Username, s.Cfg.JWTSecret)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "签发令牌失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"token": token,
		"user":  user,
	})
}

func (s *Server) Me(c *gin.Context) {
	uid := currentUserID(c)
	var user models.User
	var admInt, disInt int
	err := s.DB.QueryRow(`SELECT id, username, email, is_admin, is_disabled, created_at FROM users WHERE id = ?`, uid).
		Scan(&user.ID, &user.Username, &user.Email, &admInt, &disInt, &user.CreatedAt)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "用户不存在"})
		return
	}
	user.IsAdmin = admInt == 1
	user.IsDisabled = disInt == 1
	c.JSON(http.StatusOK, user)
}

func (s *Server) ServerInfo(c *gin.Context) {
	urls := make([]string, 0)
	ifaces, err := net.Interfaces()
	if err == nil {
		for _, iface := range ifaces {
			if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
				continue
			}
			addrs, err := iface.Addrs()
			if err != nil {
				continue
			}
			for _, addr := range addrs {
				var ip net.IP
				switch v := addr.(type) {
				case *net.IPNet:
					ip = v.IP
				case *net.IPAddr:
					ip = v.IP
				}
				if ip == nil || ip.IsLoopback() || ip.IsLinkLocalUnicast() {
					continue
				}
				if ip4 := ip.To4(); ip4 != nil {
					urls = append(urls, fmt.Sprintf("http://%s:%s", ip4.String(), s.Cfg.Port))
				}
			}
		}
	}
	c.JSON(http.StatusOK, gin.H{
		"port":     s.Cfg.Port,
		"lan_urls": urls,
	})
}
