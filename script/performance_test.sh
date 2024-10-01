#!/bin/bash

csv_path=/home/selab/Desktop/kv_benchmark/result
k8s_setup_data_dir=/home/selab/Desktop/kv_benchmark/app
nats_pv_dir=/home/selab/hdd
nats_url=http://127.0.0.1:30000
bucket_name=bucket
# times_test_run=10
times_test_run=3

# concurrent_user_array=(1 2 4 8 16 32 64 128 256 512 1024)
concurrent_user_array=(32)
# payload_array=("8" "16" "32" "64" "128" "256" "512" "1k" "2k" "4k" "8k" "16k" "32k" "64k" "128k" "256k" "512k" "1M")
payload_array=("256")

# payload_size * msg_amount(default:1000000) = 10 GB = 10737418240 B / 8G:8589934592B
max_total_size=10737418240

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

# $1=msg_amount  $2=payload_size  $3=concurrent_amount  $4=file_path $5=concurrent_proportion (percentage for put, the rest for get e.g., 50=50%)
put_get_test(){
	local _csv_path=$4
	if [ $5 -eq 100 ]
	then 
		_csv_path+="put_test.csv"
	elif [ $5 -eq 0 ]
	then
		_csv_path+="get_test.csv"
	else
		_csv_path+="put_get_test.csv"
	fi

	local temp_out_path=$4"temp.txt"

	test_time=$(date -d "now" +%Y%m%d-%H%M%S)

	concurrent_putter_amount=$(($3*$5/100))
	concurrent_getter_amount=$(($3-$concurrent_putter_amount))

	nats -s $nats_url bench put_get_test --kv --multisubject --bucket $bucket_name --storage file --msgs $1 --size $2 --pub $concurrent_putter_amount --sub $concurrent_getter_amount --dedup --request --no-progress > $temp_out_path 2>&1 
	nats_exit_stat=$?
	if [ $nats_exit_stat -eq 0 ]
	then
		echo "nats success!"	
		mawk -v test_time="$test_time" -v msg_amount="$1" -v payload_size="$2" -v concurrent_putter="$concurrent_putter_amount" -v concurrent_getter="$concurrent_getter_amount" '$1=="Pub" {printf "p@ %s@ %s@ %s@ %s@ %s@ %s@ %s\n", msg_amount, payload_size, concurrent_putter, $3, $6, $7, test_time} $1=="Sub" {printf "s@ %s@ %s@ %s@ %s@ %s@ %s@ %s\n", msg_amount, payload_size, concurrent_getter, $3, $6, $7, test_time}' $temp_out_path \
			| sed -e 's/,//g' -e 's/@/,/g' \
			>> $_csv_path
	else
		echo "nats failed!"
		echo "msg:" $(tail -n 1 $temp_out_path)
	fi
}

# $1=test_name $2=msg_amount $3=payload_size
run_concurrent_user_test(){
	for user_amount in "${concurrent_user_array[@]}"
	do
		init_nats_kv $1 

		if grep -q "k" <<< $3
		then
			payload_size_translated=$((${3%k}*1024))
		elif grep -q "M" <<< $3
		then
			payload_size_translated=$((${3%M}*1024*1024))
		else # Byte
			payload_size_translated=$(($3))
		fi

		msg_amount=$2
		total=$(($msg_amount*$payload_size_translated))
		while [ $total -gt $max_total_size ]
		do
			echo "Total size exceeds the limit"
			msg_amount=$(($msg_amount/10))
			total=$(($msg_amount*$payload_size_translated))
		done

		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting put test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $msg_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $msg_amount $3 $user_amount $csv_path/$1/ 100
			sleep 10
		done
		
		for ((i=1; i<=$times_test_run; i++))
		do
			echo "======= Starting get test $i ======="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $msg_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $msg_amount $3 $user_amount $csv_path/$1/ 0
			sleep 10
		done

		for ((i=1; i<=$times_test_run; i++))
		do
			echo "===== Starting put get test $i ====="
			echo "| Concurrent users: $user_amount"
			echo "| msg amount: $msg_amount"
			echo "| Payload size: $3"
			echo "===================================="
			put_get_test $msg_amount $3 $user_amount $csv_path/$1/ 50
			sleep 10
		done
		clean_environment
	done
}


# $1=test_name $2=append_mode 
# set -e

if [ $2 != true ]
then
	mkdir -p $csv_path/$1
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/put_test.csv
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/get_test.csv
	echo "type,msg_amount,payload_size,concurrent_user,total_msgs,throughput,throughput_unit,time" > $csv_path/$1/put_get_test.csv
fi

for payload in "${payload_array[@]}"
do
	run_concurrent_user_test $1 1000000 $payload
done

echo "Test finished!"