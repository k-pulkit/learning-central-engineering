
# Get active cluster ID
clusterid=`aws emr list-clusters --region us-east-1 --active --query "Clusters[*].Id | [0]" | sed 's/"//g'`

# copy code to s3
aws s3 cp ./app.py s3://slvr-datalake1/scripts/

# Submit the step
aws emr add-steps --cluster-id $clusterid --region us-east-1 --steps Type=Spark,Name='Test spark application',\
ActionOnFailure=CONTINUE,Args=[\
"--deploy-mode","cluster","--executor-cores","1","--num-executors","3","--driver-memory","1g","--executor-memory","5g",\
"--master","yarn",\
"--conf","spark.sql.catalogImplementation=hive",\
"s3://slvr-datalake1/scripts/app.py"] 