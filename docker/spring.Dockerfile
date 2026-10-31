FROM gradle:9.8.1-jdk25 AS build
WORKDIR /src
COPY --from=config gradle-init.gradle /opt/gradle-init.gradle
COPY . .
RUN gradle bootJar -x test --no-daemon -q --init-script /opt/gradle-init.gradle \
 && find build/libs -name '*.jar' ! -name '*-plain.jar' -exec cp {} /app.jar \;

FROM eclipse-temurin:25-jre-alpine
RUN addgroup -S app && adduser -S app -G app
USER app
COPY --from=build /app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Xmx224m -Xss512k -XX:MaxMetaspaceSize=160m -XX:+UseSerialGC -XX:TieredStopAtLevel=1"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
