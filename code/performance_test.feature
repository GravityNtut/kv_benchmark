Feature: Performance test for jetstream key value store
Scenario: Run test
    Given I have a nats with url "nats://localhost:30000"
    Given The nats server monitoring url is "localhost" and port is "30001"
    Given I have a jetstream bucket named "test"
    Given Create "100000" keys in "test" bucket, per key size "1000" bytes
    # When "Start" Performance monitoring
    When Performance test run for "100000" keys in "test" bucket, per key size "1k" bytes, with "10" concurrent clients
    # Then "Stop" Performance monitoring
    # Then Export Performance test report
    # And Delete "test" bucket