package main

import (
	"context"
	"fmt"
	"testing"

	"github.com/cucumber/godog"
	"github.com/nats-io/nats.go"
)

var natsUrl string
var natsMonitoringUrl string
var natsMonitoringPort string

func TestFeatures(t *testing.T) {
	suite := godog.TestSuite{
		ScenarioInitializer: InitializeScenario,
		Options: &godog.Options{
			Format:        "pretty",
			Paths:         []string{"./"},
			StopOnFailure: true,
			TestingT:      t,
		},
	}
	if suite.Run() != 0 {
		t.Fatal("non-zero status returned, failed to run feature tests")
	}
}

func ConnectToJS(natsUrl string) (*nats.Conn, nats.JetStreamContext, error) {
	n, err := nats.Connect(natsUrl)
	if err != nil {
		return nil, nil, fmt.Errorf("failed to connect to nats: %w", err)
	}

	js, err := n.JetStream()
	if err != nil {
		n.Close()
		return nil, nil, fmt.Errorf("failed to connect to jetstream: %w", err)
	}
	return n, js, nil
}

func InitNatsUrl(url string) error {
	natsUrl = url
	return nil
}

func InitNatsMonitoringUrl(url, port string) error {
	natsMonitoringUrl = url
	natsMonitoringPort = port
	return nil
}

func CreateBucket(bucketName string) error {
	n, js, err := ConnectToJS(natsUrl)
	if err != nil {
		return err
	}
	defer n.Close()

	js.CreateKeyValue(&nats.KeyValueConfig{Bucket: bucketName})
	return nil
}

func InitBucket(keyCount int, bucketName string, keySize int) error {
	n, js, err := ConnectToJS(natsUrl)
	if err != nil {
		return err
	}
	defer n.Close()

	kv, err := js.KeyValue(bucketName)
	if err != nil {
		return fmt.Errorf("failed to get bucket: %w", err)
	}

	for i := 0; i < keyCount; i++ {
		key := fmt.Sprintf("key-%d", i)
		value := make([]byte, keySize)
		if _, err := kv.Put(key, value); err != nil {
			return fmt.Errorf("failed to put key: %w", err)
		}
	}
	return nil
}

func RunPerformanceTest(bucketName string, keyCount int, keySize int, concurrentUser int) error {
	return nil
}

func DeleteBucket(bucketName string) error {
	n, js, err := ConnectToJS(natsUrl)
	if err != nil {
		return err
	}
	defer n.Close()

	js.DeleteKeyValue(bucketName)
	return nil
}

func InitializeScenario(ctx *godog.ScenarioContext) {
	ctx.Before(func(ctx context.Context, _ *godog.Scenario) (context.Context, error) {
		return ctx, nil
	})

	ctx.Given(`^I have a nats with url "([^"]*)"$`, InitNatsUrl)
	ctx.Given(`^The nats server monitoring url is "([^"]*)" and port is "([^"]*)"$`, InitNatsMonitoringUrl)
	ctx.Given(`^I have a jetstream bucket named "([^"]*)"$`, CreateBucket)
	ctx.Given(`^Create "([^"]*)" keys in "([^"]*)" bucket, per key size "([^"]*)" bytes$`, InitBucket)

	ctx.Then(`^Delete "([^"]*)" bucket$`, DeleteBucket)
}
