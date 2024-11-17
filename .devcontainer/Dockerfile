# Base image with Java and Ubuntu
FROM mcr.microsoft.com/devcontainers/java:0-17

# Set environment variables for Spark
ENV SCALA_VERSION=2.12.17 \
    SPARK_VERSION=3.3.0 \
    HADOOP_VERSION=3 \
    SPARK_HOME=/opt/spark \
    PATH="$PATH:/opt/spark/bin:/opt/spark/sbin"

# Install required tools and libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    unzip \
    python3 \
    python3-pip \
    build-essential \
    maven \
    && rm -rf /var/lib/apt/lists/*

# Install Scala
RUN curl -s https://downloads.lightbend.com/scala/${SCALA_VERSION}/scala-${SCALA_VERSION}.deb -o scala.deb && \
    dpkg -i scala.deb && rm scala.deb

# Install Spark
RUN curl -sL https://archive.apache.org/dist/spark/spark-${SPARK_VERSION}/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION}.tgz | \
    tar -xz -C /opt && mv /opt/spark-${SPARK_VERSION}-bin-hadoop${HADOOP_VERSION} /opt/spark

# Set working directory
WORKDIR /workspace
