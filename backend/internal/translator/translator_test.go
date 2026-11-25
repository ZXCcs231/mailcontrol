package translator

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func TestSplitChunks(t *testing.T) {
	src := strings.Repeat("hello world\n", 150)
	chunks := SplitChunks(src, 200)
	if len(chunks) < 2 {
		t.Fatalf("expected multiple chunks, got %d", len(chunks))
	}
	for i, c := range chunks {
		if len([]rune(c)) > 200 {
			t.Fatalf("chunk %d exceeded maxRunes: %d", i, len([]rune(c)))
		}
	}
}

func TestProviderFallback(t *testing.T) {
	tr := NewWithProviders([]Provider{
		{
			Name: "failing-provider",
			Fn: func(ctx context.Context, text, targetLang string) (string, error) {
				return "", errors.New("network timeout")
			},
		},
		{
			Name: "backup-provider",
			Fn: func(ctx context.Context, text, targetLang string) (string, error) {
				return "[译]" + text, nil
			},
		},
	})

	out, provider, err := tr.TranslateText(context.Background(), "Hello MailControl", "zh-CN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if provider != "backup-provider" {
		t.Fatalf("expected backup-provider, got %s", provider)
	}
	if out != "[译]Hello MailControl" {
		t.Fatalf("unexpected output: %s", out)
	}
}
