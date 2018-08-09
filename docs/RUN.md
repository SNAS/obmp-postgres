# Running OpenBMP Postgres App

Tune Linux Swapiness
--------------------

    sysctl -w vm.swappiness=10
    
    sync && echo 3 > /proc/sys/vm/drop_caches
    

Cron jobs
---------


### crontab -e

Add and update the following based on your PG settings. 

```cron
PGUSER=openbmp
PGPASSWORD=openbmp
PGHOST=127.0.0.1
PGDATABASE=openbmp

# Update aggregation table stats
*/3 * * * *      psql -c "select update_chg_stats('26 minute')"

# Update RPKI
* */2 * * *      /usr/local/openbmp/rpki_validator.py -u openbmp -p openbmp -s 127.0.0.1:8080 127.0.0.1

# Update IRR
1 1 * * *        /usr/local/openbmp/gen_whois_route.py -u openbmp -p openbmp 127.0.0.1

# Update peer rib counts
*/15 * * * *     psql -c "select update_peer_rib_counts()"

# Update origin stats
21 * * * *       psql -c "select update_global_ip_rib();"

# Purge time series data that is older than desired retention
* * 1,15 * *     psql -c "SELECT drop_chunks(interval '2 weeks');"

```

Consumer
----------------

#### Edit the configuration

You will first need to extract the configuration file and then modify it per your install/needs.  The default
will work for most as long as the Kafka instance is on the same machine/host.  Normally you will want to
at a minimum change the default kafka bootstrap server.   

##### (1) Extract the default configuration file from the JAR
```sh
unzip obmp-psql-consumer-0.1.0-SNAPSHOT.jar obmp-psql.yml
```

You should have ```obmp-psql.yml``` now in the current working directory.

##### (2) Edit the configuration file

**vi** (or sed) ```obmp-psql.yml```.  The configuration file has inline documentation.

#### Run the JAR

> ##### NOTE: 
> The configuration file is specified using the **-cf** option. 

```sh
nohup java -Xmx2g -Xms128m -XX:+UseG1GC -XX:+UnlockExperimentalVMOptions \
         -XX:InitiatingHeapOccupancyPercent=30 -XX:G1MixedGCLiveThresholdPercent=30 \
         -XX:MaxGCPauseMillis=200 -XX:ParallelGCThreads=20 -XX:ConcGCThreads=5 \
         -Duser.timezone=UTC \
         -jar obmp-psql-consumer-0.1.0-SNAPSHOT.jar \
         -cf obmp-psql.yml > psql-console.log &
```

The psql-console.log file will capture any console/STDOUT messages.  This replaces
the nohup.out file.  

The normal consumer log file will default to current working directory as ```obmp-psql.log```. This
file will automatically be rotated and stored compressed under a date folder. See below on how to
customize the log4j configuration. 


### Debug/Logging Changes
You can define your own **log4j2.yml** (yml or any format you prefer) by supplying
the ```-Dlog4j.configurationFile=<filename>``` option to java when running the JAR.   

#### Example log4j2.yml 
Below is the default ```log4j2.yml```.  Use this as a starting config. 
 
```yaml
Configuration:
  status: warn

  Appenders:
    Console:
      name: Console
      target: SYSTEM_OUT
      PatternLayout:
        Pattern: "%d{yyyy-MM-dd HH:mm:ss} [%t] %-5level %logger{36} - %msg%n"

    RollingFile:
      name: file
      fileName: "obmp-psql.log"
      filePattern: "$${date:yyyy-MM}/obmp-psql-%d{MM-dd-yyyy}-%i.log.gz"
      PatternLayout:
        Pattern: "%d{yyyy-MM-dd HH:mm:ss} [%t] %-5level %logger{36} - %msg%n"
      Policies:
        SizeBasedTriggeringPolicy:
          size: "75 MB"
      DefaultRolloverStrategy:
        max: 30

  Loggers:
    Root:
      level: info
      AppenderRef:
        ref: file
```




