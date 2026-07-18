FROM flink:1.18.1-scala_2.12-java8

ARG PAIMON_VERSION=0.8.2
ARG FLINK_KAFKA_VERSION=3.1.0-1.18
ARG FLINK_SHADED_HADOOP_VERSION=2.8.3-10.0
ARG DORIS_CONNECTOR_VERSION=24.0.1
ARG PAIMON_SHA256=243e69579df072359dcb3cd50479a30824d1506abfd2baacdc9872703435a474
ARG FLINK_KAFKA_SHA256=ad001ada5a43aca44341790a1e28135c808034be2e6b6b47e0394ad8d4d2bf0b
ARG FLINK_SHADED_HADOOP_SHA256=492b2a559f2a1dad3808b51d9a26a575dbb1202004c9f85f5059c520e0632127
ARG DORIS_CONNECTOR_SHA256=54c2510a7df905eb2a33d6abedc1c1521150ab112e9328918bb99debeb441128

RUN curl --retry 5 --retry-delay 2 --retry-all-errors -fL "https://repo.maven.apache.org/maven2/org/apache/paimon/paimon-flink-1.18/${PAIMON_VERSION}/paimon-flink-1.18-${PAIMON_VERSION}.jar" \
      -o /opt/flink/lib/paimon-flink-1.18-${PAIMON_VERSION}.jar \
    && echo "${PAIMON_SHA256}  /opt/flink/lib/paimon-flink-1.18-${PAIMON_VERSION}.jar" | sha256sum -c -

RUN curl --retry 5 --retry-delay 2 --retry-all-errors -fL "https://repo.maven.apache.org/maven2/org/apache/flink/flink-sql-connector-kafka/${FLINK_KAFKA_VERSION}/flink-sql-connector-kafka-${FLINK_KAFKA_VERSION}.jar" \
      -o /opt/flink/lib/flink-sql-connector-kafka-${FLINK_KAFKA_VERSION}.jar \
    && echo "${FLINK_KAFKA_SHA256}  /opt/flink/lib/flink-sql-connector-kafka-${FLINK_KAFKA_VERSION}.jar" | sha256sum -c -

RUN curl --retry 5 --retry-delay 2 --retry-all-errors -fL "https://repo.maven.apache.org/maven2/org/apache/flink/flink-shaded-hadoop-2-uber/${FLINK_SHADED_HADOOP_VERSION}/flink-shaded-hadoop-2-uber-${FLINK_SHADED_HADOOP_VERSION}.jar" \
      -o /opt/flink/lib/flink-shaded-hadoop-2-uber-${FLINK_SHADED_HADOOP_VERSION}.jar \
    && echo "${FLINK_SHADED_HADOOP_SHA256}  /opt/flink/lib/flink-shaded-hadoop-2-uber-${FLINK_SHADED_HADOOP_VERSION}.jar" | sha256sum -c -

RUN curl --retry 5 --retry-delay 2 --retry-all-errors -fL "https://repo.maven.apache.org/maven2/org/apache/doris/flink-doris-connector-1.18/${DORIS_CONNECTOR_VERSION}/flink-doris-connector-1.18-${DORIS_CONNECTOR_VERSION}.jar" \
      -o /opt/flink/lib/flink-doris-connector-1.18-${DORIS_CONNECTOR_VERSION}.jar \
    && echo "${DORIS_CONNECTOR_SHA256}  /opt/flink/lib/flink-doris-connector-1.18-${DORIS_CONNECTOR_VERSION}.jar" | sha256sum -c -
