#!/bin/bash

csv_path=/home/selab/Desktop/kv_benchmark/result
k8s_setup_data_dir=/home/selab/Desktop/kv_benchmark/app
nats_pv_dir=/home/selab/hdd
nats_url=http://127.0.0.1:30000
bucket_name=bucket
# times_test_run=10
times_test_run=10

# concurrent_user_array=(1 2 4 8 16 32 64 128 256 512 1024)
concurrent_user_array=(32 128 512 1024)
# payload_array=("8" "16" "32" "64" "128" "256" "512" "1k" "2k" "4k" "8k" "16k" "32k" "64k" "128k" "256k" "512k" "1M")
payload_array=("256" "1k" "4k" "8k" "512k" "1M")

# payload_size * msg_amount(default:1000000) = 10 GB = 10737418240 B / 8G:8589934592B
max_total_size=10737418240

init_nats_kv() {
	kubectl apply -f $k8s_setup_data_dir -R 
	status=$(kubectl get pod gravity-nats-2 -n ns-benchmark -o jsonpath='{.status.phase}') || true
	while [ "$status" != "Running" ]
	do
		echo "wait for nats server to be ready."
		sleep 10
		status=$(kubectl get pod gravity-nats-2 -n ns-benchmark -o jsonpath='{.status.phase}') || true
	done
		sleep 20
	nats -s $nats_url kv add $bucket_name 1>/dev/null
}

clean_environment() {
	nats -s $nats_url kv del $bucket_name -f
	kubectl delete -f $k8s_setup_data_dir -R
	# && rm -r $nats_pv_dir
}

# $1=msg_amount  $2=payload_size  $3=concurrent_amount  $4=file_path $5=concurrent_proportion (percentage for put, the rest for get e.g., 50=50%)
put_get_test(){
	local _msg_amount=$1
	local _payload_size=$2
	local _concurrent_amount=$3
	local _csv_path=$4
	local _concurrent_proportion=$5

	local temp_out_path=$_csv_path"temp.txt"

    local temp_dir="/tmp/nats_benchmark"
    mkdir -p "$temp_dir"
    local put_temp_path="${temp_dir}/put_temp_${_msg_amount}_${_payload_size}_${_concurrent_amount}.txt"
    local get_temp_path="${temp_dir}/get_temp_${_msg_amount}_${_payload_size}_${_concurrent_amount}.txt"

	
	if [ "$_concurrent_proportion" -eq 100 ]; then 
        _csv_path="${_csv_path}put_test.csv"
    elif [ "$_concurrent_proportion" -eq 0 ]; then
        _csv_path="${_csv_path}get_test.csv"
    else
        _csv_path="${_csv_path}put_get_test.csv"
    fi
    

	test_time=$(date -d "now" +%Y%m%d-%H%M%S)

	concurrent_putter_amount=$(($_concurrent_amount*$_concurrent_proportion/100))
	concurrent_getter_amount=$(($_concurrent_amount-$concurrent_putter_amount))

    echo "Starting benchmark: $_msg_amount messages, ${_payload_size}B size, $_concurrent_amount total clients"
    echo "  - PUT clients: $concurrent_putter_amount"
    echo "  - GET clients: $concurrent_getter_amount"
    

    # Put Test
    if [ "$concurrent_putter_amount" -gt 0 ]; then
        echo "Running PUT benchmark..."
        nats -s "$nats_url" bench kv put \
            --bucket "$bucket_name" \
            --msgs "$_msg_amount" \
            --size "$_payload_size" \
            --clients "$concurrent_putter_amount" \
            --no-progress > "$put_temp_path" 2>&1
        
        if [ $? -ne 0 ]; then
            echo "PUT test failed!"
            cat "$put_temp_path"
            return 1
        fi
        

		local put_msgs_sec=$(grep "Pub stats:" "$put_temp_path" | awk '{print $3}' | sed 's/,//g')
		local put_avg_ms=$(grep "Pub stats:" "$put_temp_path" | awk '{print $3}' | sed 's/,//g')
		local put_stddev_ms="0"
			
        if [ -n "$put_msgs_sec" ] && [ -n "$put_avg_ms" ] && [ -n "$put_stddev_ms" ]; then
            echo "PUT,$_msg_amount,$_payload_size,$concurrent_putter_amount,$put_msgs_sec,$put_avg_ms,$put_stddev_ms,$test_time" >> "$_csv_path"
            echo "PUT test completed: $put_msgs_sec msgs/sec, ${put_avg_ms}ms avg, ${put_stddev_ms}ms stddev"
        else
            echo "Warning: Could not parse PUT results"
            cat "$put_temp_path"
        fi
    fi
    
    # Get Test
    if [ "$concurrent_getter_amount" -gt 0 ]; then
        echo "Running GET benchmark..."
        nats -s "$nats_url" bench kv get \
            --bucket "$bucket_name" \
            --msgs "$_msg_amount" \
            --clients "$concurrent_getter_amount" \
            --no-progress > "$get_temp_path" 2>&1
        
        if [ $? -ne 0 ]; then
            echo "GET test failed!"
            cat "$get_temp_path"
            return 1
        fi
        
        local get_msgs_sec=$(grep -A 10 "Get statistics" "$get_temp_path" | grep "Msgs/Sec" | awk '{print $3}' | sed 's/,//g')
        local get_avg_ms=$(grep -A 10 "Get statistics" "$get_temp_path" | grep "Average:" | awk '{print $2}' | sed 's/ms//g')
        local get_stddev_ms=$(grep -A 10 "Get statistics" "$get_temp_path" | grep "StdDev:" | awk '{print $2}' | sed 's/ms//g')
        
        if [ -n "$get_msgs_sec" ] && [ -n "$get_avg_ms" ] && [ -n "$get_stddev_ms" ]; then
            echo "GET,$_msg_amount,$_payload_size,$concurrent_getter_amount,$get_msgs_sec,$get_avg_ms,$get_stddev_ms,$test_time" >> "$_csv_path"
            echo "GET test completed: $get_msgs_sec msgs/sec, ${get_avg_ms}ms avg, ${get_stddev_ms}ms stddev"
        else
            echo "Warning: Could not parse GET results"
            cat "$get_temp_path"
        fi
    fi
    
    echo "Benchmark complete! Results saved to $_csv_path"
    return 0
}

# $1=test_name $2=msg_amount $3=payload_size
run_concurrent_user_test(){
	local _test_name=$1
	local _msg_amount=$2
	local _payload_size=$3
	for user_amount in "${concurrent_user_array[@]}"
	do
		init_nats_kv

		if grep -q "k" <<< $_payload_size
		then
			payload_size_translated=$((${_payload_size%k}*1024))
		elif grep -q "M" <<< $_payload_size
		then
			payload_size_translated=$((${_payload_size%M}*1024*1024))
		else # Byte
			payload_size_translated=$(($_payload_size))
		fi

		total=$(($_msg_amount*$payload_size_translated))

		if [ $total -gt $max_total_size ]
		then
			echo "Total size exceeds the limit"
			_msg_amount=$(($max_total_size/$payload_size_translated))
		fi

		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting put test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $_msg_amount"
			echo "| Payload size: $_payload_size"
			echo "===================================="
			put_get_test $_msg_amount $_payload_size $user_amount $csv_path/$_test_name/ 100
			sleep 10
		done
		
		# for ((i=1; i<=$times_test_run; i++))
		# do
		# 	echo "======= Starting get test $i ======="
		# 	echo "| Concurrent users: $user_amount"
		# 	echo "| msg amount: $_msg_amount"
		# 	echo "| Payload size: $_payload_size"
		# 	echo "===================================="
		# 	put_get_test $_msg_amount $_payload_size $user_amount $csv_path/$_test_name/ 0
		# 	sleep 10
		# done

		# for ((i=1; i<=$times_test_run; i++))
		# do
		# 	echo "===== Starting put get test $i ====="
		# 	echo "| Concurrent users: $user_amount"
		# 	echo "| msg amount: $_msg_amount"
		# 	echo "| Payload size: $_payload_size"
		# 	echo "===================================="
		# 	put_get_test $_msg_amount $_payload_size $user_amount $csv_path/$_test_name/ 50
		# 	sleep 10
		# done
		clean_environment
	done
}


# $1=test_name $2=append_mode 
_test_name=$1
_append_mode=$2

if [ $_append_mode != true ]
then
	mkdir -p $csv_path/$_test_name
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$_test_name/put_test.csv
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$_test_name/get_test.csv
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$_test_name/put_get_test.csv
fi

for payload in "${payload_array[@]}"
do
	run_concurrent_user_test $_test_name 1000000 $payload
done

echo "Test finished!"