package providers

import (
	"strings"

	"mailcontrol-backend/internal/models"
)

var presets = []models.ProviderPreset{
	{
		ID:       "qq",
		Name:     "QQ 邮箱 / Foxmail",
		Domains:  []string{"qq.com", "foxmail.com"},
		IMAPHost: "imap.qq.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.qq.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "请登录网页版 QQ 邮箱 → 设置 → 账号 → 开启 IMAP/SMTP 服务，并生成 16 位授权码作为密码填入（非 QQ 登录密码）。",
	},
	{
		ID:          "163",
		Name:        "网易 163 邮箱",
		Domains:     []string{"163.com"},
		IMAPHost:    "imap.163.com",
		IMAPPort:    993,
		IMAPTLS:     "ssl",
		SMTPHost:    "smtp.163.com",
		SMTPPort:    465,
		SMTPTLS:     "ssl",
		NeedsIMAPID: true,
		AuthTip:     "请登录 163 邮箱网页版 → 设置 → POP3/SMTP/IMAP → 开启 IMAP/SMTP 服务并新增授权密码，系统会自动发送 IMAP ID 避免 Unsafe Login。",
	},
	{
		ID:          "126",
		Name:        "网易 126 邮箱",
		Domains:     []string{"126.com"},
		IMAPHost:    "imap.126.com",
		IMAPPort:    993,
		IMAPTLS:     "ssl",
		SMTPHost:    "smtp.126.com",
		SMTPPort:    465,
		SMTPTLS:     "ssl",
		NeedsIMAPID: true,
		AuthTip:     "请登录 126 邮箱网页版 → 设置 → POP3/SMTP/IMAP → 开启 IMAP/SMTP 服务并新增授权密码。",
	},
	{
		ID:       "gmail",
		Name:     "Gmail",
		Domains:  []string{"gmail.com", "googlemail.com"},
		IMAPHost: "imap.gmail.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.gmail.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "需在 Google 账号开启“两步验证”后，前往“安全性 → 应用专用密码”生成 16 位专用密码填入。",
	},
	{
		ID:       "outlook",
		Name:     "Outlook / Hotmail",
		Domains:  []string{"outlook.com", "hotmail.com", "live.com", "msn.com"},
		IMAPHost: "outlook.office365.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.office365.com",
		SMTPPort: 587,
		SMTPTLS:  "starttls",
		AuthTip:  "请确保在 Outlook 网页版设置中开启了 IMAP 访问，若账户启用了双重验证请使用应用专用密码。",
	},
	{
		ID:       "icloud",
		Name:     "iCloud 邮箱",
		Domains:  []string{"icloud.com", "me.com", "mac.com"},
		IMAPHost: "imap.mail.me.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.mail.me.com",
		SMTPPort: 587,
		SMTPTLS:  "starttls",
		AuthTip:  "请前往 account.apple.com 登录 Apple ID → 登录与安全 → App 专用密码，生成密码后填入。",
	},
	{
		ID:       "tencent_exmail",
		Name:     "腾讯企业邮",
		Domains:  []string{"exmail.qq.com"},
		IMAPHost: "imap.exmail.qq.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.exmail.qq.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "若企业开启了微信安全登录，请在企业邮设置 → 客户端专用密码中生成专用密码。",
	},
	{
		ID:       "aliyun_qiye",
		Name:     "阿里企业邮",
		Domains:  []string{"qiye.aliyun.com", "aliyun.com"},
		IMAPHost: "imap.qiye.aliyun.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.qiye.aliyun.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "请登录阿里企业邮箱网页端 → 账户与安全，检查是否开启客户端安全密码（第三方客户端专用密码）。",
	},
	{
		ID:       "feishu",
		Name:     "飞书企业邮",
		Domains:  []string{"feishu.cn"},
		IMAPHost: "imap.feishu.cn",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.feishu.cn",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "请在飞书客户端邮件设置 → 第三方邮箱客户端登录中生成专属安全密码。",
	},
	{
		ID:       "sina",
		Name:     "新浪邮箱",
		Domains:  []string{"sina.com", "sina.cn", "vip.sina.com"},
		IMAPHost: "imap.sina.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.sina.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "请登录新浪邮箱网页版 → 设置 → 客户端 POP/IMAP/SMTP，开启服务并生成客户端授权码。",
	},
	{
		ID:       "yahoo",
		Name:     "Yahoo Mail",
		Domains:  []string{"yahoo.com", "yahoo.com.cn"},
		IMAPHost: "imap.mail.yahoo.com",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "smtp.mail.yahoo.com",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "请在 Yahoo 账号安全设置中生成“应用密码（App Password）”后填入。",
	},
	{
		ID:       "custom",
		Name:     "自定义 IMAP / SMTP",
		Domains:  []string{},
		IMAPHost: "",
		IMAPPort: 993,
		IMAPTLS:  "ssl",
		SMTPHost: "",
		SMTPPort: 465,
		SMTPTLS:  "ssl",
		AuthTip:  "适用于自建邮局（如 Mailcow、Poste.io）或独立域名企业邮，请手动填写 IMAP/SMTP 服务器与端口。",
	},
}

// All 返回所有内置主流邮箱预设列表。
func All() []models.ProviderPreset {
	out := make([]models.ProviderPreset, len(presets))
	copy(out, presets)
	return out
}

// GetByID 根据预设 ID 查找配置，未找到时返回 custom 预设。
func GetByID(id string) models.ProviderPreset {
	for _, p := range presets {
		if p.ID == id {
			return p
		}
	}
	return presets[len(presets)-1]
}

// MatchByEmail 根据邮箱地址后缀匹配对应的主流邮箱预设。
func MatchByEmail(email string) models.ProviderPreset {
	parts := strings.Split(strings.TrimSpace(strings.ToLower(email)), "@")
	if len(parts) == 2 {
		domain := parts[1]
		for _, p := range presets {
			for _, d := range p.Domains {
				if d == domain {
					return p
				}
			}
		}
	}
	return presets[len(presets)-1]
}
