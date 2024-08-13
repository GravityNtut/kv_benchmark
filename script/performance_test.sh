#!/bin/bash

csv_path=~/Desktop/kv_benchmark/result/
nats_url=http://127.0.0.1:30000
bucket_name=$(date -d "now" +%Y%m%d)

# concurrent_user_array=(1 2 4 8 16 32 64 128 256 512)
concurrent_user_array=(16 256 512)

msg_array={1000000}

# payload_array=("8" "16" "32" "64" "128" "256" "512" "1k" "2k" "4k" "8k" "16k" "32k" "64k" "128k" "256k" "512k" "1M")
payload_array=("8" "16" "32")


init_nats_kv() {
	nats -s $nats_url kv add $bucket_name 1>/dev/null
	echo "type, concurrent_user, total_msgs, throughput" > $csv_path/put_test.csv
	echo "type, concurrent_user,total_msgs, throughput" > $csv_path/get_test.csv
	echo "type, concurrent_user,total_msgs, throughput" > $csv_path/put_get_test.csv
}

clean_nats_kv() {
	nats -s $nats_url kv del $bucket_name -f
}

# $1=msg  $2=payload  $3=concurrent_putter  $4=file_path
put_test(){
	nats -s $nats_url bench put_test --kv --multisubject --bucket $bucket_name --storage file --msgs $1 --size $2 --pub $3 --dedup --request --no-progress 2>/dev/null \
	| mawk '/Pub stats: /{printf "p@ %s@ %s@ %s\n",'"$3"', $3, $6}' \
	| sed -e 's/,//g' -e 's/@/,/g' \
	>> $4
}

# $1=msg  $2=payload  $3=concurrent_getter  $4=file_path
get_test(){
	nats -s $nats_url bench put_test --kv --multisubject --bucket $bucket_name --storage file --msgs $1 --size $2 --sub $3 --dedup --request --no-progress 2>/dev/null \
	| mawk '/Sub stats: /{printf "s@ %s@ %s@ %s\n",'"$3"', $3, $6}' \
	| sed -e 's/,//g' -e 's/@/,/g' \
	>> $4
}

# $1=msg  $2=payload  $3=concurrent_putter  $4=concurrent_getter  $5=file_path
put_get_test(){
	nats -s $nats_url bench put_test --kv --multisubject --bucket $bucket_name --storage file --msgs $1 --size $2 --pub $3 --sub $4 --dedup --request --no-progress 2>/dev/null \
	| mawk '/ Pub stats: /{printf "p@ %s@ %s@ %s\n",'"$3"', $3, $6} / Sub stats: /{printf "s@ %s@ %s@ %s\n",'"$4"', $3, $6}' \
	| sed -e 's/,//g' -e 's/@/,/g' \
	>> $5
}

set -e
init_nats_kv 


for user_amount in "${concurrent_user_array[@]}"
do
	for i in {1..5}
	do
		echo "put test $i start."
		put_test 10000 1k $user_amount $csv_path/put_test.csv
		sleep 10
	done
	
	for i in {1..5}
	do
		echo "get test $i start."
		get_test 10000 1k $user_amount $csv_path/get_test.csv
		sleep 10
	done

	for i in {1..5}
	do
		echo "put get test $i start."
		put_get_test 10000 1k $user_amount $user_amount $csv_path/put_get_test.csv
		sleep 10
	done
done


