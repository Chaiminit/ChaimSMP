FROM eclipse-temurin:21-jre-alpine

WORKDIR /minecraft

RUN apk add --no-cache wget curl

EXPOSE 25565

ENV JVM_OPTS="-Xms2G -Xmx8G -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=16M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:+UseStringDeduplication -XX:+OptimizeStringConcat -XX:+UseCompressedOops"

CMD java $JVM_OPTS -jar paper.jar nogui
