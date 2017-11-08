package main

import (
	"compress/gzip"
	"fmt"
	"io/ioutil"
	"os"
	"strings"

	"gopkg.in/yaml.v2"
)

type userDataFile struct {
	Path        string `yaml:"path"`
	Encoding    string `yaml:"encoding"`
	Content     string `yaml:"content"`
	Url         string
	Owner       string `yaml:"owner"`
	Permissions string `yaml:"permissions"`
}

type Conf struct {
	UserDataFiles []userDataFile `yaml:"write_files,omitempty"`
	AsScript      string
}

func check(e error) {
	if e != nil {
		panic(e)
	}
}

func (c *Conf) getConf() *Conf {
	yamlFile, err := ioutil.ReadFile("data/cloud-config.yml")
	check(err)
	err = yaml.UnmarshalStrict(yamlFile, &c)
	check(err)
	c.getConfSh()
	return c
}

func (c *Conf) getConfSh() *Conf {
	script := "#!/bin/bash\n\n"
	for _, udf := range c.UserDataFiles {
		if udf.Encoding == "b64" {
			script += fmt.Sprintf("echo '%s' | base64 --decode > %s\n\n", udf.Content, udf.Path)
		} else {
			script += fmt.Sprintf("echo '%s' > %s\n\n", udf.Content, udf.Path)
		}
	}
	script += "logger 'Done writing user-data files.'\n"
	c.AsScript = script
	return c
}

func eofWrap(s string) string {
	script := ""
	script += "\nbash <<\"EOF\"\n"
	script += fmt.Sprintf(string(s))
	script += "EOF\n"
	return script
}

func makeCliRequest() string {
	t, err := ioutil.ReadFile("/proc/sys/kernel/random/uuid")
	check(err)
	token := strings.TrimSpace(string(t))
	ami := "ami-a43c8dde"
	instanceType := "t2.micro"
	securityGroupIds := "\"sg-4e80c734\" \"sg-4d80c737\""
	subnet := "subnet-addd3791"
	tags := "'ResourceType=instance,Tags=[{Key=role,Value=aj-test}]' "

	cmd := "aws ec2 run-instances --region us-east-1 --key-name aj "
	cmd += fmt.Sprintf("--image-id %s ", ami)
	cmd += fmt.Sprintf("--instance-type %s ", instanceType)
	cmd += fmt.Sprintf("--security-group-ids %s ", securityGroupIds)
	cmd += fmt.Sprintf("--subnet-id %s ", subnet)
	cmd += fmt.Sprintf("--tag-specifications %s ", tags)
	cmd += fmt.Sprintf("--client-token %s ", token)
	cmd += fmt.Sprintf("--user-data %s ", "fileb://user-data.sh.gz")
	cmd += fmt.Sprintf("--dry-run ")
	return cmd

}

func MakeEof() {
	// write cloud-config.sh
	var c Conf
	c.getConf()
	err := ioutil.WriteFile("cloud-config.sh", []byte(c.AsScript), 0755)
	check(err)

	script := "#!/bin/bash\n\n"

	// write cloud-init.sh
	f, err := ioutil.ReadFile("data/cloud-init.sh")
	check(err)
	script += eofWrap(c.AsScript)
	script += eofWrap(string(f))

	err = ioutil.WriteFile("user-data.sh", []byte(script), 0755)
	check(err)

	// compress file with gzip
	zipped, _ := os.Create("user-data.sh.gz")
	// Create gzip writer.
	z := gzip.NewWriter(zipped)
	// Write bytes in compressed form to the file.
	x, err := ioutil.ReadFile("user-data.sh")
	check(err)
	z.Write(x)

	// Close the file.
	z.Close()
}

func multipartWrapPart(body string, filename string, contenttype string, filetype string) string {
	cc := ""
	if filename == "cloud-config" {
		cc = "#cloud-config\n# vim:filetype=yaml"
	}
	header := fmt.Sprintf(`
--MIMEBOUNDARY
Content-Disposition: attachment; filename="%s"
Content-Transfer-Encoding: 7bit
Content-Type: text/%s
Mime-Version: 1.0

%s
`, filename, contenttype, cc)
	return fmt.Sprintf("%s\n\n%s", header, body)

}

func multipartWrap(s string) string {
	header := `Content-Type: multipart/mixed; boundary="MIMEBOUNDARY"
MIME-Version: 1.0

`
	footer := "--MIMEBOUNDARY--"
	return header + s + footer

}

func main() {
	cmd := makeCliRequest()
	fmt.Println(cmd)
	//MakeEof()
	script := ""

	f, err := ioutil.ReadFile("data/cloud-config.yml")
	check(err)
	script = multipartWrapPart(string(f), "cloud-config", "cloud-config", "yaml")

	f, err = ioutil.ReadFile("data/cloud-init.sh")
	check(err)
	script += multipartWrapPart(string(f), "cloud-init", "x-shellscript", "sh")

	script = multipartWrap(script)
	fmt.Println(script)
}
