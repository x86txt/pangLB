package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"strconv"
	"strings"
	"syscall"
	"time"
)

type Result struct {
	OK     bool                   `json:"ok"`
	Now    time.Time              `json:"now"`
	Checks map[string]CheckDetail `json:"checks"`
}

type CheckDetail struct {
	OK      bool   `json:"ok"`
	Message string `json:"message,omitempty"`
}

func getenv(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func parseDurationEnv(k string, d time.Duration) time.Duration {
	v := os.Getenv(k)
	if v == "" {
		return d
	}
	dd, err := time.ParseDuration(v)
	if err != nil {
		return d
	}
	return dd
}

func parseBoolEnv(k string, d bool) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(k)))
	if v == "" {
		return d
	}
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func checkHealthFile(path string, maxAge time.Duration) (bool, string) {
	fi, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return false, "health file missing"
		}
		return false, "stat error: " + err.Error()
	}
	if fi.IsDir() {
		return false, "health file path is a directory"
	}
	if maxAge > 0 {
		age := time.Since(fi.ModTime())
		if age > maxAge {
			return false, fmt.Sprintf("health file too old: %s > %s", age.Round(time.Second), maxAge)
		}
	}
	return true, "present"
}

func checkSystemd(unit string, timeout time.Duration) (bool, string) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()

	// is-active --quiet returns exit code 0 if active
	cmd := exec.CommandContext(ctx, "systemctl", "is-active", "--quiet", unit)
	err := cmd.Run()
	if err == nil {
		return true, "active"
	}

	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		return false, "systemctl timeout"
	}

	// Non-zero exit => not active (or systemd absent)
	return false, "not active"
}

func main() {
	listenAddr := getenv("LISTEN_ADDR", ":8443")
	healthFile := getenv("NEWT_HEALTH_FILE", "/tmp/newt-healthy")
	maxAge := parseDurationEnv("MAX_AGE", 2*time.Minute)

	// TLS (recommended if Cloudflare monitor is HTTPS)
	certFile := os.Getenv("TLS_CERT_FILE")
	keyFile := os.Getenv("TLS_KEY_FILE")

	// Optional systemd check
	enableSystemd := parseBoolEnv("CHECK_SYSTEMD", false)
	systemdUnit := getenv("SYSTEMD_UNIT", "newt")
	systemdTimeout := parseDurationEnv("SYSTEMD_TIMEOUT", 1*time.Second)

	mux := http.NewServeMux()

	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		res := Result{
			Now:    time.Now().UTC(),
			Checks: map[string]CheckDetail{},
		}

		okFile, msgFile := checkHealthFile(healthFile, maxAge)
		res.Checks["newt_health_file"] = CheckDetail{OK: okFile, Message: msgFile}

		overall := okFile

		if enableSystemd {
			okSys, msgSys := checkSystemd(systemdUnit, systemdTimeout)
			res.Checks["systemd"] = CheckDetail{OK: okSys, Message: msgSys}
			overall = overall && okSys
		}

		res.OK = overall

		// Cloudflare monitor: treat 2xx as healthy, 503 as unhealthy
		if overall {
			w.WriteHeader(http.StatusOK)
		} else {
			w.WriteHeader(http.StatusServiceUnavailable)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(res)
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	srv := &http.Server{
		Addr:              listenAddr,
		Handler:           mux,
		ReadHeaderTimeout: 3 * time.Second,
		IdleTimeout:       30 * time.Second,
		TLSConfig: &tls.Config{
			MinVersion: tls.VersionTLS12,
		},
	}

	ln, err := net.Listen("tcp", listenAddr)
	if err != nil {
		log.Fatalf("listen failed: %v", err)
	}

	log.Printf("health server listening on %s (health file: %s, maxAge: %s)", listenAddr, healthFile, maxAge)

	// Graceful shutdown
	stop := make(chan os.Signal, 2)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		<-stop
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = srv.Shutdown(ctx)
	}()

	// Serve HTTP or HTTPS depending on cert env vars
	if certFile != "" && keyFile != "" {
		if _, err := os.Stat(certFile); err != nil {
			log.Fatalf("cert file invalid: %v", err)
		}
		if _, err := os.Stat(keyFile); err != nil {
			log.Fatalf("key file invalid: %v", err)
		}
		log.Fatal(srv.ServeTLS(ln, certFile, keyFile))
	} else {
		log.Fatal(srv.Serve(ln))
	}
}

// (Optional helper) If you ever need a distinct TCP port: export PORT and LISTEN_ADDR=":PORT"
func init() {
	if p := os.Getenv("PORT"); p != "" && os.Getenv("LISTEN_ADDR") == "" {
		if _, err := strconv.Atoi(p); err == nil {
			_ = os.Setenv("LISTEN_ADDR", net.JoinHostPort("", p))
		}
	}
}
