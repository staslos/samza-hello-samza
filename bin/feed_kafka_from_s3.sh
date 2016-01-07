#!/bin/bash

# Script uses Pipe Viewer to throttle traffic to Kafka
# yum install pv

if [ $# -ne 3 ]; then
    echo "Need args: s3 path, topic, throttling rate"
    echo "Ads example:    sh feed_kafka_from_s3.sh s3://com.domdex.log/2016/01/05/00/*_ad.log.gz imp-raw 512k"
    echo "Bids example:   sh feed_kafka_from_s3.sh s3://com.domdex.rtb/2016/01/05/00/*_bids.log.gz bid-raw 4096k"
	exit 1
fi

S3_PATH=$1
KAFKA_TOPIC=$2
THROTTLING="pv -L $3"

if [ -z $KAFKA_HOME ]; then KAFKA_HOME=/srv/kafka/kafka_2.10-0.8.2.1; fi
if [ -z $KAFKA_BROKER_LIST ]; then KAFKA_BROKER_LIST=kfk001.dev.us-east-1.mgnt.cc:9092; fi

KAFKA_PRODUCER=$KAFKA_HOME/bin/kafka-console-producer.sh

echo \> S3 logs to Kafka Ingestion
echo \>
echo \> Read from S3: $S3_PATH
echo \> Send to Kafka: $KAFKA_BROKER_LIST/$KAFKA_TOPIC
echo \>
echo \> Press any key to continue... \(CTRL+C to abort\)
read -s -n 1 any_key
echo \> Transfer begins!

for d in $(hadoop fs -ls $S3_PATH | awk '{print $6}')
do
	echo Sending $d to Kafka
	hadoop fs -text $d | $THROTTLING | $KAFKA_PRODUCER --broker-list $KAFKA_BROKER_LIST --topic $KAFKA_TOPIC --metadata-expiry-ms 2000
done