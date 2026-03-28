package main

import (
	"archive/zip"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/fsnotify/fsnotify"
)

var (
	mu         sync.RWMutex
	clientZip  []byte
	clientHash string
)

func buildZip(clientDir string) ([]byte, string, error) {
	var buf bytes.Buffer
	w := zip.NewWriter(&buf)

	err := filepath.WalkDir(clientDir, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(clientDir, path)
		// skip .DS_Store
		if filepath.Base(rel) == ".DS_Store" {
			return nil
		}
		f, err := w.Create(rel)
		if err != nil {
			return err
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		_, err = f.Write(data)
		return err
	})
	if err != nil {
		return nil, "", err
	}
	w.Close()

	data := buf.Bytes()
	h := sha256.Sum256(data)
	hash := hex.EncodeToString(h[:])
	return data, hash, nil
}

func rebuild(clientDir string) {
	data, hash, err := buildZip(clientDir)
	if err != nil {
		log.Println("build zip error:", err)
		return
	}
	mu.Lock()
	clientZip = data
	clientHash = hash
	mu.Unlock()
	log.Printf("client rebuilt: hash=%s size=%d", hash[:8], len(data))
}

func main() {
	clientDir := "../client"
	if len(os.Args) > 1 {
		clientDir = os.Args[1]
	}
	clientDir, _ = filepath.Abs(clientDir)

	rebuild(clientDir)

	watcher, err := fsnotify.NewWatcher()
	if err != nil {
		log.Fatal(err)
	}
	defer watcher.Close()

	// Watch clientDir and all subdirectories
	filepath.WalkDir(clientDir, func(path string, d fs.DirEntry, _ error) error {
		if d.IsDir() {
			watcher.Add(path)
		}
		return nil
	})

	var debounce *time.Timer
	go func() {
		for {
			select {
			case event, ok := <-watcher.Events:
				if !ok {
					return
				}
				if event.Has(fsnotify.Write) || event.Has(fsnotify.Create) || event.Has(fsnotify.Remove) {
					if debounce != nil {
						debounce.Stop()
					}
					debounce = time.AfterFunc(2*time.Second, func() {
						rebuild(clientDir)
					})
				}
			case err, ok := <-watcher.Errors:
				if !ok {
					return
				}
				log.Println("watcher error:", err)
			}
		}
	}()

	http.HandleFunc("/client/version", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		hash := clientHash
		mu.RUnlock()
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(map[string]string{"hash": hash})
	})

	http.HandleFunc("/client", func(w http.ResponseWriter, r *http.Request) {
		mu.RLock()
		data := clientZip
		mu.RUnlock()
		w.Header().Set("Content-Type", "application/zip")
		w.Header().Set("Content-Length", fmt.Sprintf("%d", len(data)))
		w.Write(data)
	})

	addr := ":20200"
	if len(os.Args) > 2 {
		addr = ":" + os.Args[2]
	}
	log.Printf("serving on %s, watching %s", addr, clientDir)
	log.Fatal(http.ListenAndServe(addr, nil))

	_ = io.Discard // suppress unused import
}
