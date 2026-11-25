package config

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"strconv"
)

// Config 保存服务端运行时配置。
type Config struct {
	Host                string
	Port                string
	DataDir             string
	JWTSecret           string
	EncKey              []byte
	DefaultSyncInterval int
}

type persistedSecrets struct {
	JWTSecret string `json:"jwt_secret"`
	EncKeyB64 string `json:"enc_key_b64"`
}

// Load 从环境变量与本地 secrets.json 加载或初始化配置。
func Load() (*Config, error) {
	host := getEnv("HOST", "0.0.0.0")
	port := getEnv("PORT", "8080")
	dataDir := getEnv("DATA_DIR", "./data")
	syncInterval := 180
	if raw := os.Getenv("DEFAULT_SYNC_INTERVAL"); raw != "" {
		if v, err := strconv.Atoi(raw); err == nil && v >= 30 {
			syncInterval = v
		}
	}

	if err := os.MkdirAll(dataDir, 0755); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Join(dataDir, "attachments"), 0755); err != nil {
		return nil, err
	}

	jwtSecret := os.Getenv("JWT_SECRET")
	encKeyRaw := os.Getenv("ENC_KEY")

	secretsPath := filepath.Join(dataDir, "secrets.json")
	var persisted persistedSecrets
	if data, err := os.ReadFile(secretsPath); err == nil {
		_ = json.Unmarshal(data, &persisted)
	}

	dirty := false
	if jwtSecret == "" {
		if persisted.JWTSecret != "" {
			jwtSecret = persisted.JWTSecret
		} else {
			buf := make([]byte, 32)
			if _, err := rand.Read(buf); err != nil {
				return nil, err
			}
			jwtSecret = hex.EncodeToString(buf)
			persisted.JWTSecret = jwtSecret
			dirty = true
		}
	}

	var encKey []byte
	if encKeyRaw != "" {
		encKey = deriveKey32(encKeyRaw)
	} else if persisted.EncKeyB64 != "" {
		decoded, err := base64.StdEncoding.DecodeString(persisted.EncKeyB64)
		if err == nil && len(decoded) == 32 {
			encKey = decoded
		}
	}
	if len(encKey) != 32 {
		buf := make([]byte, 32)
		if _, err := rand.Read(buf); err != nil {
			return nil, err
		}
		encKey = buf
		persisted.EncKeyB64 = base64.StdEncoding.EncodeToString(buf)
		dirty = true
	}

	if dirty {
		raw, err := json.MarshalIndent(persisted, "", "  ")
		if err != nil {
			return nil, err
		}
		if err := os.WriteFile(secretsPath, raw, 0600); err != nil {
			return nil, err
		}
	}

	return &Config{
		Host:                host,
		Port:                port,
		DataDir:             dataDir,
		JWTSecret:           jwtSecret,
		EncKey:              encKey,
		DefaultSyncInterval: syncInterval,
	}, nil
}

func deriveKey32(input string) []byte {
	if decoded, err := base64.StdEncoding.DecodeString(input); err == nil && len(decoded) == 32 {
		return decoded
	}
	if decoded, err := hex.DecodeString(input); err == nil && len(decoded) == 32 {
		return decoded
	}
	sum := sha256.Sum256([]byte(input))
	return sum[:]
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
