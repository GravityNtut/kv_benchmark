#!/bin/bash

source /home/bbg/ntut/kv_benchmark/script/config.conf

init_nats_kv() {
	kubectl apply -f $k8s_setup_data_dir -R 
	status=$(kubectl get pod gravity-nats-2 -n ns-benchmark -o jsonpath='{.status.phase}') || true
	while [ "$status" != "Running" ]
	do
		echo "wait for nats server to be ready."
		sleep 10
		status=$(kubectl get pod gravity-nats-2 -n ns-benchmark -o jsonpath='{.status.phase}') || true
	done
		sleep 30
	nats -s $nats_url kv add $bucket_name 1>/dev/null
}

clean_environment() {
	nats -s $nats_url kv del $bucket_name -f
	kubectl delete -f $k8s_setup_data_dir -R
	sleep 5
}

# $1=msg_amount  $2=payload_size  $3=concurrent_amount  $4=file_path $5=concurrent_proportion (percentage for put, the rest for get e.g., 50=50%)
put_get_test(){
	local _msg_amount=$1
	local _payload_size=$2
	local _concurrent_amount=$3
	local _csv_path=$4
	local _concurrent_proportion=$5

	local temp_out_path=$_csv_path"temp.txt"

	if [ $_concurrent_proportion -eq 100 ]
	then 
		_csv_path+="put_test.csv"
	elif [ $_concurrent_proportion -eq 0 ]
	then
		_csv_path+="get_test.csv"
	else
		_csv_path+="put_get_test.csv"
	fi

	test_time=$(date -d "now" +%Y%m%d-%H%M%S)

	concurrent_putter_amount=$(($_concurrent_amount*$_concurrent_proportion/100))
	concurrent_getter_amount=$(($_concurrent_amount-$concurrent_putter_amount))

	nats -s $nats_url bench put_get_test --kv --multisubject --bucket $bucket_name --storage file --msgs $_msg_amount --size $_payload_size --pub $concurrent_putter_amount --sub $concurrent_getter_amount --dedup --request --no-progress > $temp_out_path 2>&1 
	nats_exit_stat=$?
	if [ $nats_exit_stat -eq 0 ]
	then
		echo "success!"	
		mawk -v test_time="$test_time" -v msg_amount="$_msg_amount" -v payload_size="$_payload_size" -v concurrent_putter="$concurrent_putter_amount" -v concurrent_getter="$concurrent_getter_amount" '$1=="Pub" {printf "p@ %s@ %s@ %s@ %s@ %s@ %s@ %s\n", msg_amount, payload_size, concurrent_putter, $3, $6, $7, test_time} $1=="Sub" {printf "s@ %s@ %s@ %s@ %s@ %s@ %s@ %s\n", msg_amount, payload_size, concurrent_getter, $3, $6, $7, test_time}' $temp_out_path \
			| sed -e 's/,//g' -e 's/@/,/g' \
			>> $_csv_path
	else
		echo "nats failed!"
		echo "error msg:" $(tail -n 1 $temp_out_path)
		exit 1
	fi
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
		
		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting get test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $_msg_amount"
			echo "| Payload size: $_payload_size"
			echo "===================================="
			put_get_test $_msg_amount $_payload_size $user_amount $csv_path/$_test_name/ 0
			sleep 10
		done

		for ((i=1; i<=$times_test_run; i++))
		do
			echo "===== Starting put get test $i ====="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $_msg_amount"
			echo "| Payload size: $_payload_size"
			echo "===================================="
			put_get_test $_msg_amount $_payload_size $user_amount $csv_path/$_test_name/ 50
			sleep 10
		done
		clean_environment
	done
}


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