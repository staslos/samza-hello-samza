# Magnetic Imp-Bid Join PoC using Samza

###Intro
- Repartition impressions and bids by the same key (auction id) and send them to related topic/partition.
- That way n-th partition of impressions topic will have the same auctions as n-th partition of bids topic.
- When reading those topics, Samza will provide data from n-th partition on both topics to the same task, 
i.e. all the necessary information to make a join will end up on the same machine/process.
- Samza's local state storage (KV store) provides a lookup mechanism to make a join.
- Increasing amount of partitions/concurrent tasks allows the join to scale linearly (nothing-share architecture).
- Tested on local Samza grid and at Scale on Hadoop cluster
- Please note, media partner impressions just dropped during the join, since there is no related bids

###TODO
- Deploy to Hadoop cluster and test at scale
- Performance of the state storage for lookups, size of the data we can hold (KV storage works well on SSD, 
but can suffer on regular HDD)
- Performance of the state storage at clean up since it pauses main processing, 
i.e. window() method blocks process() method
- Restoring from checkpoint; can we control read rates so two streams stay more or less aligned?
- Replays from Kafka at some time interval; need to maintain timestamp->offsets/topic/partition information
- Replays from s3? If we can keep big enough window, it's easier that with Spark, 
because data streams alignment is not so critical

### Run PoC on local Samza grid
Use following commands to run PoC locally.

```
# For the first time run to set up Samza environment
bin/grid bootstrap

# Start the grid
bin/grid start all

# Create Kafka topics (some of them created automatically, but here we do it explicitly)
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-raw --zookeeper localhost:2181 --partitions 1 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-raw --zookeeper localhost:2181 --partitions 1 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-meta --zookeeper localhost:2181 --partitions 4 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-meta --zookeeper localhost:2181 --partitions 4 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-error --zookeeper localhost:2181 --partitions 1 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-error --zookeeper localhost:2181 --partitions 1 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-bid-joined --zookeeper localhost:2181 --partitions 1 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-store-changelog --zookeeper localhost:2181 --partitions 4 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-store-changelog --zookeeper localhost:2181 --partitions 4 --replication 1
sh deploy/kafka/bin/kafka-topics.sh --list --zookeeper localhost:2181

# Build and deploy project
mvn clean package
rm -rf deploy/samza
mkdir -p deploy/samza
tar -xvf ./target/hello-samza-0.10.0-dist.tar.gz -C deploy/samza

# Start raw events repartition
deploy/samza/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory \
    --config-path=file://$PWD/deploy/samza/config/magnetic-feed.properties
# Start join process
deploy/samza/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory \
    --config-path=file://$PWD/deploy/samza/config/magnetic-join.properties
    
# Logs can be found:
tail -100f deploy/yarn/logs/userlogs/application_XXXXXXXXXX_XXXX/container_XXXXXXXXXX_XXXX_XX_XXXXXX/{logs}

# Start Kafka concole producer to submit some ad logs
sh deploy/kafka/bin/kafka-console-producer.sh --broker-list localhost:9092 --topic imp-raw

# Copy paste ad log event(impression)
	V=magnetic.domdex.com	t=[10/Dec/2015:00:00:00 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705601&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=

# If matching bid log is not submitted, adding those impressions will lead to cleanup of previous one from imp-store
# when next time window() function runs (you can see this happen by tailing imp-store-changelog topic, it's delayed, so be patient)
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705611&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705621&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705631&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705641&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705651&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705661&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705671&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705681&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=
	V=magnetic.domdex.com	t=[10/Dec/2015:01:00:01 +0000]	a=	u=-	c=c4706fc6df6f48b683d6aca71863f99f	m=GET	l=/ahtm	q=js=t&r=c&b=39634&c=57391&n=9468&id=650e33b95a1449705691&sz=728x90&s=onetravel.com&u=c4706fc6df6f48b683d6aca71863f99f&f=1&cat=00-00&ms=558536&kw=&kwcat=&dp=&a=VmjAfwAOX7AUNL2pBW_4_aHw4x_o6q1Wy3wCYA	s=200	b=2849	r=http://www.onetravel.com/	a0=2601:346:404:4e50:b090:77f3:4343:fbc1	ua=Mozilla/4.0 (compatible; MSIE 8.0; Windows NT 6.1; WOW64; Trident/4.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; .NET4.0C; .NET4.0E; InfoPath.3)	d=1570	rpt=ahtm	x=

# Start Kafka concole producer to submit some bid logs
sh deploy/kafka/bin/kafka-console-producer.sh --broker-list localhost:9092 --topic bid-raw

# Copy-paste matching bid log event
1449705600	45799578e9064ca5b4e87af2aba77092	161.253.120.255	US	511	DC	20016	America/New_York	650e33b95a1449705601	5668c08c0008a5e80a1f1acb6c0f76fa	g	1		thegradcafe.com	728x90	1	00-00	1054641	9115	54663	38227				54663,52593,51249,51246,55928,50856,46309,52454,32235,50944		Mozilla/5.0 (Macintosh; Intel Mac OS X 10_10_5) AppleWebKit/601.3.9 (KHTML, like Gecko) Version/9.0.2 Safari/601.3.9	http://thegradcafe.com/survey/index.php	1	875	1000	1000	en	iab_tech		85	85	45	6500	45	15	25000	1000	600	1000	1000	1000	1000	1000	magnetic_ctr_variable_price	1.0	2.64151881627e-05								2015120920	-4.05492019653				2015120920		Safari	Mac_OS_X	00-00		0	1				70	n_a

# Monitor propagation of data thru system
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper localhost:2181 --topic imp-meta
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper localhost:2181 --topic bid-meta
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper localhost:2181 --topic imp-error
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper localhost:2181 --topic bid-error
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper localhost:2181 --topic imp-bid-join

# Shutdown everything
bin/grid stop all
```


### Run on Hadoop cluster (CDH)
Use following commands to run PoC on Magnetic's Dev Hadoop cluster.

```
# If you didn't do this yet, set up Samza environment
bin/grid bootstrap

# Create topics on Magnetic's Dev Kafka
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-raw --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 1 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-raw --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 1 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-meta --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 30 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-meta --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 30 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-error --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 1 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-error --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 1 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-bid-joined --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 1 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic imp-store-changelog --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 30 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --create --topic bid-store-changelog --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --partitions 30 --replication 1 --config retention.ms=8640000 --config segment.bytes=536870912
sh deploy/kafka/bin/kafka-topics.sh --list --zookeeper zk001.dev.us-east-1.mgnt.cc:2181

# Build and deploy project to Magnetic's Dev Hadoop cluster
mvn clean package -Denv=cdh5.4.0
scp -r ./target/hello-samza-0.10.0-dist.tar.gz hadoop-client01.dev.aws.mgnt.cc:/srv/stanislav/samza/hello-samza
ssh hadoop-client01.dev.aws.mgnt.cc
mkdir -p /srv/$USER/samza/hello-samza
cd /srv/$USER/samza/hello-samza
export HADOOP_CONF_DIR=/etc/hadoop/conf
rm -rf deploy/samza
mkdir -p deploy/samza
tar -xvf hello-samza-0.10.0-dist.tar.gz -C deploy/samza
hadoop fs -rm -r -f samza/*
hadoop fs -put hello-samza-0.10.0-dist.tar.gz samza

# Start raw events repartition
deploy/samza/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory \
    --config-path=file://$PWD/deploy/samza/config/magnetic-feed-cdh.properties
# Start join process
deploy/samza/bin/run-job.sh --config-factory=org.apache.samza.config.factories.PropertiesConfigFactory \
    --config-path=file://$PWD/deploy/samza/config/magnetic-join-cdh.properties
    
# Check jobs running in Hadoop Yarn:
# http://ds-hnn002.dev.aws.mgnt.cc:8088/cluster/scheduler

# Start Kafka concole producer to read ad logs from s3 and send them to Kafka
sh deploy/samza/bin/feed_kafka_from_s3.sh s3://com.domdex.log/2016/01/06/00/*_ad.log.gz imp-raw 512k

# Start Kafka concole producer to read bid logs from s3 and send them to Kafka (in another terminal)
sh deploy/samza/bin/feed_kafka_from_s3.sh s3://com.domdex.rtb/2016/01/06/00/*_bids.log.gz bid-raw 8192k

# Monitor propagation of data thru system (from local machine)
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --topic imp-meta
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --topic bid-meta
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --topic imp-error
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --topic bid-error
sh deploy/kafka/bin/kafka-console-consumer.sh  --zookeeper zk001.dev.us-east-1.mgnt.cc:2181 --topic imp-bid-joined

```