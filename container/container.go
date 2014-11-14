package container

import (
	"io"
	"log"
	"net/http"

	"github.com/cloudfoundry-incubator/garden/api"
	"github.com/pivotal-cf-experimental/garden-dot-net/process"

	"fmt"
	"time"

	"code.google.com/p/go.net/websocket"
)

type container struct {
	tupperwareURL string
}

func NewContainer(tupperwareURL string) *container {
	return &container{
		tupperwareURL: tupperwareURL,
	}
}

func (container *container) Handle() string {
	return "containerhandle"
}

func (container *container) Stop(kill bool) error {
	return nil
}

func (container *container) Info() (api.ContainerInfo, error) {
	return api.ContainerInfo{}, nil
}

func (container *container) StreamIn(dstPath string, tarStream io.Reader) error {
	url := container.tupperwareURL + "/api/containers/" + container.Handle() + "/files"

	req, err := http.NewRequest("PUT", url, tarStream)
	if err != nil {
		return err
	}
	_, err = http.DefaultClient.Do(req)

	return err
}
func (container *container) StreamOut(srcPath string) (io.ReadCloser, error) {
	url := container.tupperwareURL + "/api/containers/" + container.Handle() + "/files" + "?source=" + srcPath
	resp, err := http.Get(url)
	if err != nil {
		return nil, err
	}
	return resp.Body, nil
}

func (container *container) LimitBandwidth(limits api.BandwidthLimits) error {
	return nil
}
func (container *container) CurrentBandwidthLimits() (api.BandwidthLimits, error) {
	return api.BandwidthLimits{}, nil
}

func (container *container) LimitCPU(limits api.CPULimits) error {
	return nil
}

func (container *container) CurrentCPULimits() (api.CPULimits, error) {
	return api.CPULimits{}, nil
}

func (container *container) LimitDisk(limits api.DiskLimits) error {
	return nil
}
func (container *container) CurrentDiskLimits() (api.DiskLimits, error) {
	return api.DiskLimits{}, nil
}

func (container *container) LimitMemory(limits api.MemoryLimits) error {
	return nil
}
func (container *container) CurrentMemoryLimits() (api.MemoryLimits, error) {
	return api.MemoryLimits{}, nil
}

func (container *container) NetIn(hostPort, containerPort uint32) (uint32, uint32, error) {
	// FIXME ; probably not even good for this mock
	return 80, 80, nil
}
func (container *container) NetOut(network string, port uint32) error {
	return nil
}

func (container *container) Run(processSpec api.ProcessSpec, processIO api.ProcessIO) (api.Process, error) {
	origin := "http://localhost/"
	url := "ws://localhost:2000/websocket"
	ws, err := websocket.Dial(url, "", origin)
	if err != nil {
		log.Fatal(err)
	}
	fmt.Println("Jane")
	websocket.JSON.Send(ws, processSpec)
	time.Sleep(1 * time.Second)
	return process.DotNetProcess{}, nil
}

func (container *container) Attach(uint32, api.ProcessIO) (api.Process, error) {
	return process.DotNetProcess{}, nil
}

func (container *container) GetProperty(name string) (string, error) {
	return "A Property Value", nil
}

func (container *container) SetProperty(name string, value string) error {
	return nil
}
func (container *container) RemoveProperty(name string) error {
	return nil
}
