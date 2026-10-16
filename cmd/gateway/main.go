package main

import (
	"fmt"
	"net/http"
)

type Engine interface {
	start()
}

type V8Engine struct {
}

func (v V8Engine) start() {

}

func main() {
	http.HandleFunc("/v1/status", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("content-type", "Application/Json")
		fmt.Fprint(w, "ok")
	})
	fmt.Println("Server has started...")

	if err := http.ListenAndServe(":8081", nil); err != nil {
		panic(err)
	}

}
