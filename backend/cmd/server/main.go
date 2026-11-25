package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"mailcontrol-backend/internal/api"
	"mailcontrol-backend/internal/config"
	"mailcontrol-backend/internal/db"
	"mailcontrol-backend/internal/syncer"
)

func main() {
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("加载配置失败: %v", err)
	}

	dbPath := filepath.Join(cfg.DataDir, "mailcontrol.db")
	conn, err := db.Open(dbPath)
	if err != nil {
		log.Fatalf("初始化数据库失败: %v", err)
	}
	defer func() { _ = conn.Close() }()

	hub := syncer.NewHub()
	scheduler := syncer.NewScheduler(conn, cfg, hub)

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go scheduler.Start(ctx)

	router := api.NewRouter(conn, cfg, hub, scheduler)
	addr := cfg.Host + ":" + cfg.Port
	httpSrv := &http.Server{
		Addr:    addr,
		Handler: router,
	}

	go func() {
		log.Printf("MailControl 后端服务已启动，监听地址: http://%s (data: %s)", addr, cfg.DataDir)
		if err := httpSrv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("HTTP 服务启动失败: %v", err)
		}
	}()

	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit

	log.Println("正在优雅关闭 MailControl 后端服务...")
	cancel()
	shutdownCtx, shutdownCancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer shutdownCancel()
	_ = httpSrv.Shutdown(shutdownCtx)
}
