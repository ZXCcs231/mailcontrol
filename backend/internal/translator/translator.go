package translator

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// Language 描述支持的目标翻译语言。
type Language struct {
	Code string `json:"code"`
	Name string `json:"name"`
}

// SupportedLanguages 列出常用的翻译目标语言。
var SupportedLanguages = []Language{
	{Code: "zh-CN", Name: "简体中文"},
	{Code: "zh-TW", Name: "繁体中文"},
	{Code: "en", Name: "英语"},
	{Code: "ja", Name: "日语"},
	{Code: "ko", Name: "韩语"},
	{Code: "fr", Name: "法语"},
	{Code: "de", Name: "德语"},
	{Code: "es", Name: "西班牙语"},
	{Code: "ru", Name: "俄语"},
	{Code: "pt", Name: "葡萄牙语"},
	{Code: "ar", Name: "阿拉伯语"},
}

// Provider 定义单个翻译渠道函数。
type Provider struct {
	Name string
	Fn   func(ctx context.Context, text, targetLang string) (string, error)
}

// Translator 聚合多个免费翻译渠道，按优先级自动容灾降级。
type Translator struct {
	client    *http.Client
	mu        sync.Mutex
	edgeToken string
	edgeExp   time.Time
	providers []Provider
}

// New 创建内置免费多渠道翻译器（Edge 翻译 -> Google 免费接口 -> MyMemory 免费接口）。
func New() *Translator {
	t := &Translator{
		client: &http.Client{Timeout: 15 * time.Second},
	}
	t.providers = []Provider{
		{Name: "Edge 免费翻译", Fn: t.translateEdge},
		{Name: "Google 免费翻译", Fn: t.translateGoogle},
		{Name: "MyMemory 免费翻译", Fn: t.translateMyMemory},
	}
	return t
}

// NewWithProviders 用于单元测试注入自定义渠道列表。
func NewWithProviders(providers []Provider) *Translator {
	return &Translator{
		client:    &http.Client{Timeout: 5 * time.Second},
		providers: providers,
	}
}

// TranslateText 将文本翻译为目标语言，自动分段并依次尝试可用免费渠道。
func (t *Translator) TranslateText(ctx context.Context, text, targetLang string) (string, string, error) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return "", "", nil
	}
	targetLang = NormalizeLang(targetLang)

	var errs []string
	for _, p := range t.providers {
		out, err := t.translateWithProvider(ctx, p, text, targetLang)
		if err == nil && strings.TrimSpace(out) != "" {
			return out, p.Name, nil
		}
		if err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", p.Name, err))
		}
	}
	return "", "", fmt.Errorf("所有免费翻译渠道均暂时不可用（%s）", strings.Join(errs, "; "))
}

func (t *Translator) translateWithProvider(ctx context.Context, p Provider, text, targetLang string) (string, error) {
	chunks := SplitChunks(text, 1400)
	var out strings.Builder
	for i, chunk := range chunks {
		if strings.TrimSpace(chunk) == "" {
			out.WriteString(chunk)
			continue
		}
		res, err := p.Fn(ctx, chunk, targetLang)
		if err != nil {
			return "", err
		}
		if i > 0 && !strings.HasSuffix(out.String(), "\n") {
			out.WriteString("\n")
		}
		out.WriteString(res)
	}
	return out.String(), nil
}

// SplitChunks 按换行符将长文本拆分成不超过 maxRunes 的片段。
func SplitChunks(text string, maxRunes int) []string {
	if maxRunes <= 0 {
		maxRunes = 1400
	}
	if len([]rune(text)) <= maxRunes {
		return []string{text}
	}

	lines := strings.Split(text, "\n")
	var chunks []string
	var cur strings.Builder
	curLen := 0

	flush := func() {
		if cur.Len() > 0 {
			chunks = append(chunks, cur.String())
			cur.Reset()
			curLen = 0
		}
	}

	for _, line := range lines {
		r := []rune(line)
		if len(r) > maxRunes {
			flush()
			for i := 0; i < len(r); i += maxRunes {
				end := i + maxRunes
				if end > len(r) {
					end = len(r)
				}
				chunks = append(chunks, string(r[i:end]))
			}
			continue
		}
		need := len(r) + 1
		if curLen > 0 && curLen+need > maxRunes {
			flush()
		}
		if cur.Len() > 0 {
			cur.WriteByte('\n')
			curLen++
		}
		cur.WriteString(line)
		curLen += len(r)
	}
	flush()
	return chunks
}

// NormalizeLang 规范化常见语言代码。
func NormalizeLang(code string) string {
	c := strings.TrimSpace(code)
	if c == "" {
		return "zh-CN"
	}
	lower := strings.ToLower(c)
	switch lower {
	case "zh", "zh-cn", "zh_cn", "zh-hans":
		return "zh-CN"
	case "zh-tw", "zh_tw", "zh-hk", "zh-hant":
		return "zh-TW"
	default:
		return c
	}
}

func (t *Translator) getEdgeToken(ctx context.Context) (string, error) {
	t.mu.Lock()
	if t.edgeToken != "" && time.Now().Before(t.edgeExp) {
		tok := t.edgeToken
		t.mu.Unlock()
		return tok, nil
	}
	t.mu.Unlock()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://edge.microsoft.com/translate/auth", nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

	resp, err := t.client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("auth status %d", resp.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(resp.Body, 16*1024))
	if err != nil {
		return "", err
	}
	tok := strings.TrimSpace(string(b))
	if tok == "" {
		return "", errors.New("empty auth token")
	}

	t.mu.Lock()
	t.edgeToken = tok
	t.edgeExp = time.Now().Add(8 * time.Minute)
	t.mu.Unlock()
	return tok, nil
}

func (t *Translator) translateEdge(ctx context.Context, text, targetLang string) (string, error) {
	tok, err := t.getEdgeToken(ctx)
	if err != nil {
		return "", err
	}

	edgeLang := targetLang
	switch targetLang {
	case "zh-CN":
		edgeLang = "zh-Hans"
	case "zh-TW":
		edgeLang = "zh-Hant"
	}

	endpoint := "https://api-edge.cognitive.microsofttranslator.com/translate?api-version=3.0&to=" + url.QueryEscape(edgeLang)
	payload, _ := json.Marshal([]map[string]string{{"Text": text}})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(payload))
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	req.Header.Set("Content-Type", "application/json")

	resp, err := t.client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode == http.StatusUnauthorized {
		t.mu.Lock()
		t.edgeToken = ""
		t.mu.Unlock()
		return "", errors.New("edge token expired")
	}
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("status %d", resp.StatusCode)
	}

	var parsed []struct {
		Translations []struct {
			Text string `json:"text"`
		} `json:"translations"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&parsed); err != nil {
		return "", err
	}
	if len(parsed) == 0 || len(parsed[0].Translations) == 0 {
		return "", errors.New("empty response")
	}
	return parsed[0].Translations[0].Text, nil
}

func (t *Translator) translateGoogle(ctx context.Context, text, targetLang string) (string, error) {
	u := fmt.Sprintf(
		"https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=%s&dt=t&q=%s",
		url.QueryEscape(targetLang),
		url.QueryEscape(text),
	)
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0")

	resp, err := t.client.Do(req)
	if err != nil {
		return "", err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("status %d", resp.StatusCode)
	}

	var raw []interface{}
	if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil {
		return "", err
	}
	if len(raw) == 0 {
		return "", errors.New("empty response")
	}
	segments, ok := raw[0].([]interface{})
	if !ok {
		return "", errors.New("unexpected response format")
	}
	var out strings.Builder
	for _, seg := range segments {
		pair, ok := seg.([]interface{})
		if ok && len(pair) > 0 {
			if s, ok := pair[0].(string); ok {
				out.WriteString(s)
			}
		}
	}
	if out.Len() == 0 {
		return "", errors.New("no translated text")
	}
	return out.String(), nil
}

func (t *Translator) translateMyMemory(ctx context.Context, text, targetLang string) (string, error) {
	// MyMemory 单次最多支持 500 字符
	chunks := SplitChunks(text, 450)
	var out strings.Builder
	for i, chunk := range chunks {
		if strings.TrimSpace(chunk) == "" {
			continue
		}
		u := fmt.Sprintf(
			"https://api.mymemory.translated.net/get?q=%s&langpair=Autodetect%%7C%s",
			url.QueryEscape(chunk),
			url.QueryEscape(targetLang),
		)
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return "", err
		}
		resp, err := t.client.Do(req)
		if err != nil {
			return "", err
		}
		var parsed struct {
			ResponseStatus int `json:"responseStatus"`
			ResponseData   struct {
				TranslatedText string `json:"translatedText"`
			} `json:"responseData"`
		}
		err = json.NewDecoder(resp.Body).Decode(&parsed)
		_ = resp.Body.Close()
		if err != nil {
			return "", err
		}
		if parsed.ResponseStatus != 200 || strings.TrimSpace(parsed.ResponseData.TranslatedText) == "" {
			return "", fmt.Errorf("status %d", parsed.ResponseStatus)
		}
		if i > 0 {
			out.WriteByte('\n')
		}
		out.WriteString(parsed.ResponseData.TranslatedText)
	}
	return out.String(), nil
}
