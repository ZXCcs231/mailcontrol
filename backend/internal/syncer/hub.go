package syncer

import (
	"sync"
	"time"
)

// Event 表示通过 SSE 推送到客户端的实时事件。
type Event struct {
	Type      string      `json:"type"`
	AccountID int64       `json:"account_id,omitempty"`
	Label     string      `json:"label,omitempty"`
	Count     int         `json:"count,omitempty"`
	Message   string      `json:"message,omitempty"`
	Timestamp time.Time   `json:"timestamp"`
	Data      interface{} `json:"data,omitempty"`
}

// Hub 按 user_id 管理所有活跃 SSE 客户端订阅通道。
type Hub struct {
	mu          sync.RWMutex
	subscribers map[int64]map[chan Event]struct{}
}

// NewHub 创建 SSE 事件广播中心。
func NewHub() *Hub {
	return &Hub{
		subscribers: make(map[int64]map[chan Event]struct{}),
	}
}

// Subscribe 注册用户的 SSE 事件通道并返回取消订阅函数。
func (h *Hub) Subscribe(userID int64) (<-chan Event, func()) {
	ch := make(chan Event, 32)
	h.mu.Lock()
	if h.subscribers[userID] == nil {
		h.subscribers[userID] = make(map[chan Event]struct{})
	}
	h.subscribers[userID][ch] = struct{}{}
	h.mu.Unlock()

	cancel := func() {
		h.mu.Lock()
		if set, ok := h.subscribers[userID]; ok {
			if _, exists := set[ch]; exists {
				delete(set, ch)
				close(ch)
			}
			if len(set) == 0 {
				delete(h.subscribers, userID)
			}
		}
		h.mu.Unlock()
	}
	return ch, cancel
}

// Publish 向指定用户所有在线客户端广播事件（非阻塞）。
func (h *Hub) Publish(userID int64, evt Event) {
	if evt.Timestamp.IsZero() {
		evt.Timestamp = time.Now()
	}
	h.mu.RLock()
	set := h.subscribers[userID]
	for ch := range set {
		select {
		case ch <- evt:
		default:
		}
	}
	h.mu.RUnlock()
}
