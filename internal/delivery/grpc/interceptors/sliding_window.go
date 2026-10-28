package interceptors

import (
	"context"
	"crypto/rand"
	"fmt"
	"os"
	"time"

	"github.com/redis/go-redis/v9"
)

// slidingWindow uses one atomic Redis script for pruning, checking and reserving
// a request. Script.Run also reloads the script after Redis loses its script cache.
type slidingWindow struct {
	rdb    *redis.Client
	script *redis.Script
	limit  int
	window int // seconds
}

func newSlidingWindow(rdb *redis.Client, limit, window int, path string) (*slidingWindow, error) {
	if rdb == nil || limit <= 0 || window <= 0 {
		return nil, fmt.Errorf("Redis client, positive limit and positive window are required")
	}
	content, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	script := redis.NewScript(string(content))
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := script.Load(ctx, rdb).Err(); err != nil {
		return nil, err
	}
	return &slidingWindow{rdb: rdb, script: script, limit: limit, window: window}, nil
}

func (w *slidingWindow) reserve(ctx context.Context, key string) (string, bool, error) {
	id := rand.Text()
	result, err := w.script.Run(ctx, w.rdb, []string{key}, w.limit, w.window, id).Int64()
	return id, result == 1, err
}
