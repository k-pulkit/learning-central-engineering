## Step to run on EMR ##
## Read Table => Print schema => Transform => Save as a table

from pyspark.sql import SparkSession

print("Starting Application")
# create spark session
spark = SparkSession.builder.getOrCreate()

print("Step1")
# read table, assumes that database and table is present in the Glue catalog
df = spark.read.table("ghactivitydb.rawghactivity")

print("Step2")
# show
df.show()

print("Step3")
# some transformation
df2 = df.selectExpr("created_at", "public", "actor.id", "actor.login as actorlogin")

print("Step4")
# show and save
df2.show()
df2.write.option("header", True).format("parquet").mode("overwrite").option("path", "s3://slvr-datalake1/processed/ghactivitytest").saveAsTable("ghactivitydb.test2")

print("Step5")
# Query and show results
spark.sql("select actorlogin, count(*) as `cnt` from ghactivitydb.test2 group by actorlogin order by cnt desc").show()
print("Ending Application")