package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"

	"mailcontrol-backend/internal/syncer"
)

// Events 提供基于 SSE 的实时同步与新邮件推送。
func (s *Server) Events(c *gin.Context) {
	uid := currentUserID(c)
	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no")

	flusher, ok := c.Writer.(http.Flusher)
	if !ok {
		c.Status(http.StatusInternalServerError)
		return
	}

	subCh, cancel := s.Hub.Subscribe(uid)
	defer cancel()

	writeSSE(c, syncer.Event{Type: "connected", Timestamp: time.Now()})
	flusher.Flush()

	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()

	ctx := c.Request.Context()
	for {
		select {
		case <-ctx.Done():
			return
		case evt, ok := <-subCh:
			if !ok {
				return
			}
			writeSSE(c, evt)
			flusher.Flush()
		case <-heartbeat.C:
			_, _ = fmt.Fprint(c.Writer, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func writeSSE(c *gin.Context, evt syncer.Event) {
	b, err := json.Marshal(evt)
	if err != nil {
		return
	}
	_, _ = fmt.Fprintf(c.Writer, "event: %s\ndata: %s\n\n", evt.Type, string(b))
}
