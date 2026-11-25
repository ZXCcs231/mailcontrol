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

func TestTranslateHTMLPreservesStructureAndSplitsMismatch(t *testing.T) {
	tr := NewWithProviders([]Provider{
		{
			Name: "mock",
			Fn: func(ctx context.Context, text, targetLang string) (string, error) {
				if strings.Contains(text, "\n") {
					// 模拟破坏换行对齐的行为，验证二分拆分兜底逻辑
					return strings.ReplaceAll(text, "\n", " | "), nil
				}
				return "[ZH]" + text, nil
			},
		},
	})

	src := `<div style="color:#333"><p>Hello <strong>World</strong></p><p><a href="https://example.com">Verify now</a></p><code>git status</code><p>https://example.com/path</p><img src="a.png" alt="logo"/></div>`
	out, prov, err := tr.TranslateHTML(context.Background(), src, "zh-CN")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if prov != "mock" {
		t.Fatalf("expected provider mock, got %s", prov)
	}
	for _, want := range []string{
		`style="color:#333"`,
		`<strong>[ZH]World</strong>`,
		`<a href="https://example.com">[ZH]Verify now</a>`,
		`<code>git status</code>`,
		`<p>https://example.com/path</p>`,
		`<img src="a.png" alt="logo"/>`,
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("expected %q in output:\n%s", want, out)
		}
	}
}
