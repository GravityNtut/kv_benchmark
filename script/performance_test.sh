#!/bin/bash

csv_path=/home/selab/Desktop/kv_benchmark/result
k8s_setup_data_dir=/home/selab/Desktop/kv_benchmark/app
nats_pv_dir=/home/selab/hdd
nats_url=http://127.0.0.1:30000
bucket_name=bucket
times_test_run=10

# concurrent_user_array=(1 2 4 8 16 32 64 128 256 512 1024)
concurrent_user_array=(32 128)
# payload_array=("8" "16" "32" "64" "128" "256" "512" "1k" "2k" "4k" "8k" "16k" "32k" "64k" "128k" "256k" "512k" "1M")
payload_array=("256" "1k" "4k" "8k")

# $1=$test_name
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

# $1=msg_amount  $2=payload_size  $3=concurrent_amount  $4=file_path  $5=concurrent_proportion (percentage for put, the rest for get e.g., 50=50%)
put_get_test(){
	test_time=$(date -d "now" +%Y%m%d-%H%M%S)

	if [ "$#" -eq 5 ]
	then
		concurrent_putter_amount=$(($3*$5/100))
		concurrent_getter_amount=$(($3-$concurrent_putter_amount))
	else
		echo "Invalid parameters"
		exit 1
	fi

	nats -s $nats_url bench put_get_test --kv --multisubject --bucket $bucket_name --storage file --msgs $1 --size $2 --pub $concurrent_putter_amount --sub $concurrent_getter_amount --dedup --request --no-progress 2>/dev/null \
	| mawk -v test_time="$test_time" -v payload_size="$2" -v concurrent_putter="$concurrent_putter_amount" -v concurrent_getter="$concurrent_getter_amount" '$1=="Pub" {printf "p@ %s@ %s@ %s@ %s@ %s@ %s\n", payload_size, concurrent_putter, $3, $6, $7, test_time} $1=="Sub" {printf "s@ %s@ %s@ %s@ %s@ %s@ %s\n", payload_size, concurrent_getter, $3, $6, $7, test_time}' \
	| sed -e 's/,//g' -e 's/@/,/g' \
	>> $4
}


# $1=test_name $2=msg_amount $3=payload_size
run_concurrent_user_test(){
	for user_amount in "${concurrent_user_array[@]}"
	do
		init_nats_kv $1 
		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting put test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $2 $3 $user_amount $csv_path/$1/put_test.csv 100
			sleep 10
		done
		
		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting get test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $2 $3 $user_amount $csv_path/$1/get_test.csv 0
			sleep 10
		done

		for ((i=1; i<=$times_test_run; i++))
		do
			echo "===== Starting put get test $i ====="
			echo "| Concurrent users: $user_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $2 $3 $user_amount $csv_path/$1/put_get_test.csv 50
			sleep 10
		done
		clean_environment
	done
}


# $1=test_name $2=append_mode 
set -e

if [ $2 != true ]
then
	mkdir -p $csv_path/$1
	echo "type,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/put_test.csv
	echo "type,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/get_test.csv
	echo "type,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/put_get_test.csv
fi

for payload in "${payload_array[@]}"
do
	run_concurrent_user_test $1 1000000 $payload
done
