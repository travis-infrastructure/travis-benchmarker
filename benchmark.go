package main

import "fmt"
import "encoding/json"

type Image struct {
	Name   string
	Method string
}

type Images struct {
	List []Image
}

type DockerConfig struct {
	AsJSON      string
	GraphDriver string
	FileSystem  string
}

type DockerConfigs struct {
	List []DockerConfig
}

type Benchmark struct {
	Image        Image
	DockerConfig DockerConfig
}

type BenchmarkGroup struct {
	List []Benchmark
}

func (bm *Benchmark) print() {
	fmt.Printf(
		"graph driver: %s\n"+
			"       image: %s\n"+
			"      method: %s\n"+
			"  filesystem: %s\n",
		bm.DockerConfig.GraphDriver,
		bm.Image.Name,
		bm.Image.Method,
		bm.DockerConfig.FileSystem,
	)
}

func (bm *Benchmark) dockerConfig() (string, error) {
	asJSON := map[string]string{}
	asJSON["foo"] = "bar"
	ret, err := json.Marshal(asJSON)
	if err != nil {
		return "", err
	}
	return string(ret), nil
}

func main() {
	todo := []Benchmark{}

	images := []Image{
		Image{Name: "travisci/amethyst", Method: "pull"},
		Image{Name: "travisci/amethyst", Method: "load"},
	}

	graphDrivers := []string{
		"overlay2",
		"devicemapper (direct-lvm)", // https://docs.docker.com/engine/userguide/storagedriver/device-mapper-driver/
	}

	fileSystems := []string{
		"xfs",
		"btrfs",
		"ext4",
	}

	for _, gd := range graphDrivers {
		for _, i := range images {
			for _, fs := range fileSystems {
				bm := Benchmark{
					Image: i,
					DockerConfig: DockerConfig{
						GraphDriver: gd,
						FileSystem:  fs,
					},
				}
				todo = append(todo, bm)
			}
		}
	}
	for i, bm := range todo {
		fmt.Println("Benchmark group:", i)
		bm.print()
		jsonConfig, err := bm.dockerConfig()
		if err != nil {
			fmt.Println(err)
		}
		fmt.Println(jsonConfig)
		fmt.Println("-------------------------------")
	}
}

/*
Ensure compatability:
- upstart vs. systemd

*/
