import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

#算四分位數
def median(data_frame):
    data_frame = sorted(data_frame)
    length = len(data_frame)
    mid, rem = divmod(length, 2)
    if rem:
        return data_frame[:mid], data_frame[mid + 1:], data_frame[mid]
    else:
        return data_frame[:mid], data_frame[mid:], (data_frame[mid - 1] + data_frame[mid]) / 2

def drop_outlier(df: pd.DataFrame):
    if( len(df) > 1):
        lHalf, rHalf, Q2 = median( df['throughput'] )
        Q1 = median(lHalf)[2]
        Q3 = median(rHalf)[2]
        IQR = Q3 - Q1
        upperbound = Q3 + IQR * 1.5
        lowerbound = Q1 - IQR * 1.5
        clean_index = df[ (df['throughput']<lowerbound) | (df['throughput']>upperbound) ].index
        df = df.drop(clean_index)
    return df

def sort_func(data):
    data = str(data).strip().upper() 
    if 'K' in data:
        data_num = int(data.replace('K','')) * 1024
    elif 'M' in data:
        data_num = int(data.replace('M','')) * 1024 * 1024
    else:
        data_num = int(data)
    return data_num 
    

def run_plt(subject, csv_file_path, output_png_path):
    # Create a plot
    plt.figure()

    # Load the CSV file
    df = pd.read_csv(csv_file_path)

    concurrent_user_set = set(df['concurrent_user'])

    # Convert units to MB/sec
    filter = (df['throughput_unit'].str.contains('KB/sec'))
    df.loc[filter, 'throughput'] = df.loc[filter, 'throughput'] / 1024

    filter = (df['throughput_unit'].str.contains('GB/sec'))
    df.loc[filter, 'throughput'] = df.loc[filter, 'throughput'] * 1024

    # Group by 'type', 'payload_size', and 'concurrent_user'
    grouped_df = df.groupby(['type', 'payload_size', 'concurrent_user'])
    processed_dfs = []

    for _, group in grouped_df:
        group = drop_outlier(group)
        processed_dfs.append(group)

    result_df = pd.concat(processed_dfs)
    grouped_df = result_df.groupby(['type', 'payload_size', 'concurrent_user'])

    # Calculate the mean of 'throughput' for each group
    average_throughput = grouped_df['throughput'].mean().reset_index()

    put_get_df = average_throughput.groupby(['payload_size', 'concurrent_user'])
    sum_put_get_df = put_get_df['throughput'].sum().reset_index()
    if( subject == 'PUT GET Test'):
            sum_put_get_df['concurrent_user'] = sum_put_get_df['concurrent_user'] * 2
            concurrent_user_set = { x * 2 for x in concurrent_user_set}
    print(sum_put_get_df)
    sorted_concurrent_user_set = sorted(concurrent_user_set)
    for concurrent_user in sorted_concurrent_user_set:
        filter = (sum_put_get_df['concurrent_user'] == concurrent_user)
        throughput_list = list(sum_put_get_df.loc[filter, 'throughput'])
        payload_list = list(sum_put_get_df.loc[filter, 'payload_size'])
        zipped = zip(payload_list, throughput_list)
        sorted_zipped = sorted(zipped, key=lambda x: sort_func(x[0]))
        sorted_payload_list, sorted_throughput_list = zip(*sorted_zipped)
        plt.plot(sorted_payload_list,sorted_throughput_list, marker='o', markersize=4, label=str(concurrent_user))

    plt.legend(title='concurrent_user')
    plt.xlabel('payload size(Byte)')
    plt.ylabel('throughput(MB/sec)')
    plt.title(subject)

    plt.savefig(output_png_path)

run_plt('PUT Test', 'result/test_1001/put_test.csv', 'result/plt/test_1001/put_test.png')
run_plt('GET Test', 'result/test_1001/get_test.csv', 'result/plt/test_1001/get_test.png')
run_plt('PUT GET Test', 'result/test_1001/put_get_test.csv', 'result/plt/test_1001/put_get_test.png')

