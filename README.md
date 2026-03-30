# KV Benchmark 專案

本專案用於在 Kubernetes 環境下，針對 NATS Key-Value 儲存進行效能測試與監控。

## 目錄結構
- `deployments/docker-k8s/`：混合方案（K8s 跑 NATS，Docker Compose 跑 OTel/Prometheus/Grafana）
- `deployments/k8s/`：全 K8s 方案（NATS + OTel + Prometheus + Grafana 全部在 Kubernetes）
- `script/`：效能測試腳本（如 performance_test.sh）
- `result/`：效能測試結果輸出

## 主要功能
- 自動部署 NATS Key-Value 叢集於 Kubernetes
- 使用 shell script 進行效能測試（PUT/GET）
- 以 Prometheus + OpenTelemetry Collector + Grafana 監控 NATS 叢集狀態與效能

## 觀測架構 A（Docker + K8s，保留）
- K8s：NATS Pod（含 `nats_exporter` sidecar）
- Docker Compose：OpenTelemetry Collector + Prometheus + Grafana

資料流：`NATS -> nats_exporter -> OTel Collector -> Prometheus -> Grafana`

### 啟動（Docker + K8s）

```bash
kubectl apply -f deployments/docker-k8s/k8s/ -R
docker compose -f deployments/docker-k8s/compose/docker-compose.yaml up -d
```

### 關閉（Docker + K8s）

```bash
docker compose -f deployments/docker-k8s/compose/docker-compose.yaml down
kubectl delete -f deployments/docker-k8s/k8s/ -R
```

## 觀測架構 B（全 K8s）

另外提供一套全 K8s 觀測部署，檔案位於 `deployments/k8s/`，資料流如下：

`NATS Pod -> nats-exporter(7777) -> OTel Collector(9464) -> Prometheus(9090) -> Grafana(3000)`

### 啟動全 K8s 觀測

```bash
kubectl apply -f deployments/k8s/base/ -R
kubectl apply -f deployments/k8s/monitoring/ -R
```

### 查看狀態

```bash
kubectl get pod -n ns-monitoring
kubectl get svc -n ns-monitoring
```

### 存取方式

- Prometheus：`http://<NodeIP>:30900`
- Grafana：`http://<NodeIP>:30300`（帳密：admin / pass）

### 關閉全 K8s 觀測

```bash
kubectl delete -f deployments/k8s/monitoring/ -R
kubectl delete -f deployments/k8s/base/ -R
```

## 注意事項
- 請確認 NFS 伺服器與 StorageClass 設定正確，PVC/PV 狀態需為 Bound。
- 若遇到 PV 為 Released，請參考 README 或 FAQ 處理。
- Grafana 預設帳號密碼：`admin` / `pass`，可透過 SSH port forwarding 於本地瀏覽 http://localhost:3000。
- 若 Grafana 遇到 Data Source 無法抓取，可先檢查 `http://localhost:9090/targets` 是否有 `otel_collector` target 且狀態為 `UP`。

## 常用指令
- 查看 PV/PVC 狀態：
  ```bash
  kubectl get pv
  kubectl get pvc -n ns-benchmark
  ```
- 查看 Pod 狀態：
  ```bash
  kubectl get pod -n ns-benchmark
  ```

## 測試指令範例

### 關閉 swap
```bash
sudo swapoff -a
```

### NATS KV 操作與效能測試
```bash
# 設定 alias
alias n="nats -s http://172.16.168.11:30000"

# 建立 bucket
n kv add bar

# 若要清空並重跑（建議，不用 --purge）
n kv del bar -f
n kv add bar

# 預載資料
n bench kv put --bucket bar --storage file --msgs 1000000 --size 100 --clients 10 --csv=put_warmup.csv

# PUT 測試
nats -s http://172.16.168.11:30000 bench kv put --bucket bar --storage file --msgs 1000000 --size 1k --clients 30 --csv=put_test.csv

# GET 測試
nats -s http://172.16.168.11:30000 bench kv get --bucket bar --msgs 1000000 --clients 30 --csv=get_test.csv

# PUT/GET 混合測試
nats -s http://172.16.168.11:30000 bench kv put --bucket bar --storage file --msgs 1000000 --size 1k --clients 15 --csv=put_mix.csv
nats -s http://172.16.168.11:30000 bench kv get --bucket bar --msgs 1000000 --clients 15 --csv=get_mix.csv
```

### 監控
```bash
nats-top -s 172.16.168.11 -m 30001
```

### 後台執行與結果輸出
```bash
nohup nats -s http://172.16.168.11:30000 bench kv put --bucket bar --storage file --msgs 1000000 --size 1k --clients 30 --csv=result/put_test_bg.csv --no-progress &> tmp/out.txt &
```

### 直接輸出結果到 CSV
```bash
nats -s http://172.16.168.11:30000 bench kv put --bucket bar --storage file --msgs 1000000 --size 1k --clients 30 --csv=result/put_test.csv
nats -s http://172.16.168.11:30000 bench kv get --bucket bar --msgs 1000000 --clients 30 --csv=result/get_test.csv
```

### 進階 CSV 檢視
```bash
column -s, -t result/put_test.csv | head
column -s, -t result/get_test.csv | head
```

### 執行效能測試腳本
```bash
nohup ./script/performance_test.sh emulate_test > log.txt 2>&1 &
nohup ./script/performance_test.sh big_test_copy true >> result/big_test_copy/log.txt 2>&1 &
```

### 查看當前執行的 performance_test.sh
```bash
ps -aux|grep script/performance_test.sh
```


