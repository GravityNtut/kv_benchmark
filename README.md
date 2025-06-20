# KV Benchmark 專案

本專案用於在 Kubernetes 環境下，針對 NATS Key-Value 儲存進行效能測試與監控。

## 目錄結構
- `app/`：Kubernetes 部署相關 YAML 檔案（NATS、PV、Service 等）
- `script/`：效能測試腳本（如 performance_test.sh）
- `result/`：效能測試結果輸出
- `docker-compose.yaml`：本地監控（Prometheus、Grafana）組態

## 主要功能
- 自動部署 NATS Key-Value 叢集於 Kubernetes
- 使用 shell script 進行效能測試（PUT/GET）
- 以 Prometheus + Grafana 監控 NATS 叢集狀態與效能

## 快速啟動
1. **部署 NATS 叢集**
   ```bash
   kubectl apply -f app/ -R
   ```
2. **啟動監控服務（本地）**
   ```bash
   docker-compose up -d
   ```
3. **執行效能測試**
   ```bash
   cd script
   bash performance_test.sh <test_name> <append_mode>
   ```

## 注意事項
- 請確認 NFS 伺服器與 StorageClass 設定正確，PVC/PV 狀態需為 Bound。
- 若遇到 PV 為 Released，請參考 README 或 FAQ 處理。
- Grafana 預設帳號密碼：`admin` / `pass`，可透過 SSH port forwarding 於本地瀏覽 http://localhost:3000。

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

# 預載資料
n bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 100 --pub 10 --csv=test.csv --dedup --request --purge

# PUT 測試
nats -s http://172.16.168.11:30000 bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --pub 30 --dedup --request

# GET 測試
nats -s http://172.16.168.11:30000 bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --sub 30 --dedup --request

# PUT/GET 混合測試
nats -s http://172.16.168.11:30000 bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --sub 15 --pub 15 --dedup --request
```

### 監控
```bash
nats-top -s 172.16.168.11 -m 30001
```

### 後台執行與結果輸出
```bash
nohup nats -s http://172.16.168.11:30000 bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --pub 30 --dedup --request --no-progress &> tmp/out.txt &
```

### 直接輸出結果到 CSV
```bash
nats -s http://172.16.168.11:30000 bench foo --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --pub 30 --dedup --request --no-progress | mawk '/Pub stats: /{printf "%s %s ", $3, $6} /min/{printf "%s %s %s\n", $2, $5, $8}' >> ~/Desktop/kv_benchmark/result/test_result.csv
```

### 進階 awk/sed 處理
```bash
n bench put_test --kv --multisubject --bucket bar --storage file --msgs 1000000 --size 1k --pub 15 --sub 15 --dedup --request --no-progress 2>/dev/null | mawk '/Pub stats: /{printf "%s@ %s@ ", $3, $6} /min/{printf "%s@ %s@ %s\n", $5, $2, $8}' | sed -e 's/,//g' -e 's/@/,/g' >> testFile.txt

mawk '/Pub stats: /{printf "%s@ %s@ ", $3, $6} /min/{printf "%s@ %s@ %s\n", $5, $2, $8} /Sub stats: /{printf "%s@ %s@ ", $3, $6}'
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


