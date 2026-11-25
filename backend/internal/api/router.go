package api

import (
	"database/sql"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/syncer"
	"mailcontrol-backend/internal/translator"
)

// NewRouter 装配所有 API 路由及中间件。
func NewRouter(conn *sql.DB, cfg *config.Config, hub *syncer.Hub, scheduler *syncer.Scheduler) *gin.Engine {
	gin.SetMode(gin.ReleaseMode)
	r := gin.New()
	r.Use(gin.Recovery(), CORSMiddleware())

	srv := &Server{
		DB:         conn,
		Cfg:        cfg,
		Hub:        hub,
		Scheduler:  scheduler,
		Translator: translator.New(),
	}

	apiGroup := r.Group("/api")
	{
		apiGroup.GET("/health", srv.Health)
		apiGroup.GET("/providers", srv.ListProviders)
		apiGroup.POST("/auth/register", srv.Register)
		apiGroup.POST("/auth/login", srv.Login)

		auth := apiGroup.Group("")
		auth.Use(srv.AuthMiddleware(), srv.SyncBroadcastMiddleware())
		{
			auth.GET("/auth/me", srv.Me)
			auth.GET("/server-info", srv.ServerInfo)

			auth.GET("/accounts", srv.ListAccounts)
			auth.POST("/accounts", srv.CreateAccount)
			auth.PUT("/accounts/:id", srv.UpdateAccount)
			auth.DELETE("/accounts/:id", srv.DeleteAccount)
			auth.POST("/accounts/test", srv.TestAccount)
			auth.POST("/accounts/:id/sync", srv.TriggerSync)

			auth.GET("/folders", srv.ListFolders)
			auth.GET("/stats", srv.GetStats)

			auth.GET("/messages", srv.ListMessages)
			auth.GET("/messages/:id", srv.GetMessage)
			auth.PATCH("/messages/:id", srv.PatchMessage)
			auth.DELETE("/messages/:id", srv.DeleteMessage)
			auth.POST("/messages/batch", srv.BatchMessages)
			auth.POST("/messages/send", srv.SendMessage)
			auth.POST("/messages/drafts", srv.SaveDraft)
			auth.PUT("/messages/drafts/:id", srv.SaveDraft)

			auth.GET("/attachments/:id/download", srv.DownloadAttachment)

			auth.GET("/tags", srv.ListTags)
			auth.POST("/tags", srv.CreateTag)
			auth.PUT("/tags/:id", srv.UpdateTag)
			auth.DELETE("/tags/:id", srv.DeleteTag)

			auth.GET("/rules", srv.ListRules)
			auth.GET("/rules/presets", srv.ListRulePresets)
			auth.POST("/rules/presets/apply", srv.ApplyRulePresets)
			auth.POST("/rules", srv.CreateRule)
			auth.PUT("/rules/:id", srv.UpdateRule)
			auth.DELETE("/rules/:id", srv.DeleteRule)
			auth.POST("/rules/:id/run", srv.RunRule)

			auth.GET("/signatures", srv.ListSignatures)
			auth.POST("/signatures", srv.CreateSignature)
			auth.PUT("/signatures/:id", srv.UpdateSignature)
			auth.DELETE("/signatures/:id", srv.DeleteSignature)

			auth.GET("/translate/languages", srv.GetTranslateLanguages)
			auth.POST("/translate/text", srv.TranslateText)
			auth.POST("/messages/:id/translate", srv.TranslateMessage)

			auth.GET("/events", srv.Events)
		}
	}

	return r
}
