# Nats key-value benchmark
This repository benchmarks the NATS JetStream key-value store. It tests the relationship between the number of concurrent users and payload sizes.

## File Structure

The file structure is as follows:
- `app` directory contains the YAML files to start the required services.
- `config` directory contains the JetStream configuration, which needs to be copied to the NFS server.
- `grafana_data` directory contains Grafana data storage.
- `result` directory contains the test results where the test outputs will be stored.
- `script` directory contains three files:
    - `performance_test.sh` file is the main executing shell script to run tests.
    - `config.conf` file contains the global variables configuration needed to set up different testing environments and different test data.
    - `analysis_data.py` file analyzes the test results and outputs benchmark figures.
- `docker-compose.yaml` file describes the Prometheus and Grafana services.
- `prometheus.yml` file defines the settings for Prometheus.
```
.
├── app
│   ├── 00-namespace.yaml
│   ├── 02-nfs-pv.yml
│   ├── 10-gravity_nats.yaml
│   └── service.yaml
├── config
│   └── jetstream.conf
├── grafana_data
│   ├── ...
├── result
├── script
│   ├── analysis_data.py
│   ├── config.conf
│   └── performance_test.sh
├── docker-compose.yaml
├── prometheus.yml
```

## Usage

Clone the repository:
```sh
git clone git@github.com:GravityNtut/kv_benchmark.git
cd kv_benchmark
```
Modify the following files for custom Kubernetes setup:
- `app/02-nfs-pv.yml`
- `script/config.conf`

Copy the `config` directory to the NFS server.

Run the test script in the background and output the log to `log.txt`:
```sh
nohup ./script/performance_test.sh > log.txt 2>&1 &
```

Use the `ps` command to check if the process is running:
```sh
ps -aux | grep script/performance_test.sh 
```

After finishing the tests, modify the last line in `analysis_data.py` to navigate to (or specify the path to) the test result file
```python
# Change [test_1001] to your test folder
run_plt('PUT Test', 'result/test_1001/put_test.csv', 'result/plt/test_1001/put_test.png')
run_plt('GET Test', 'result/test_1001/get_test.csv', 'result/plt/test_1001/get_test.png')
run_plt('PUT GET Test', 'result/test_1001/put_get_test.csv', 'result/plt/test_1001/put_get_test.png')
```