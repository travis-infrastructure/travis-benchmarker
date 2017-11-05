package main

import "fmt"
import "encoding/json"

type Image struct {
	Name string
}

type Images struct {
	List []Image
}

type DockerConfig struct {
	AsJSON      string
	GraphDriver string
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
			"      method: %s\n",
		bm.DockerConfig.GraphDriver,
		bm.Image.Name,
		"pull",
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
	fmt.Println("hi")
	todo := []Benchmark{}

	images := []Image{
		Image{"travisci/amethyst"},
		Image{"travisci/whatever"},
	}

	graphDrivers := []string{
		"overlay2",
		"btrfs",
		"direct-lvm",
	}

	for _, gd := range graphDrivers {
		for _, i := range images {
			bm := Benchmark{
				Image: i,
				DockerConfig: DockerConfig{
					GraphDriver: gd,
				},
			}
			todo = append(todo, bm)
		}
	}
	fmt.Println(todo)
	for i, bm := range todo {
		fmt.Println("Benchmark group:", i)
		bm.print()
		//fmt.Println(bm)
		jsonConfig, err := bm.dockerConfig()
		if err != nil {
			fmt.Println(err)
		}
		fmt.Println(jsonConfig)
		fmt.Println("------")
	}
}
