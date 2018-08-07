-- -----------------------------------------------------------------------
-- BEGIN Schema
--     VERSION 1.0
-- -----------------------------------------------------------------------

-- SET TIME ZONE 'UTC';

-- enable timescale DB
CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE;

-- Use different disk for history/log/time series
CREATE TABLESPACE timeseries LOCATION '/data1/postgres/ts';


-- -----------------------------------------------------
-- Enums used in tables
-- -----------------------------------------------------
CREATE TYPE opState as enum ('up', 'down', '');
CREATE TYPE user_role as enum ('admin', 'oper', '');

-- -----------------------------------------------------
-- Tables and base, non dependant functions
-- -----------------------------------------------------

-- Table structure for table geo_ip
DROP TABLE IF EXISTS geo_ip;
CREATE TABLE geo_ip (
  family                smallint        NOT NULL,
  ip_start              inet            NOT NULL,
  ip_end                inet            NOT NULL,
  country               char(2)         NOT NULL,
  stateprov             varchar(80)     NOT NULL,
  city                  varchar(80)     NOT NULL,
  latitude              float           NOT NULL,
  longitude             float           NOT NULL,
  timezone_offset       float           NOT NULL,
  timezone_name         varchar(64)     NOT NULL,
  isp_name              varchar(128)    NOT NULL,
  connection_type       varchar(64),
  organization_name     varchar(128),
  PRIMARY KEY (ip_start)
);
CREATE INDEX ON geo_ip (stateprov);
CREATE INDEX ON geo_ip (country);
CREATE INDEX ON geo_ip (family);
CREATE INDEX ON geo_ip (ip_end);
CREATE INDEX ON geo_ip (ip_start,ip_end);

INSERT INTO geo_ip VALUES
	(4, '0.0.0.0', '255.255.255.255', 'US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default'),
	(6, '::', 'FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF:FFFF', 'US', 'WA', 'Seattle', 47.6129432, -122.4821472, 0, 'UTC', 'default', 'default', 'default');

-- CREATE OR REPLACE FUNCTION find_geo_ip_start(ip inet)
--	RETURNS inet AS $$
--	DECLARE
--	        geo_ip_start inet := NULL;
--	BEGIN
--
--	    SELECT ip_start INTO geo_ip_start
--	    FROM geo_ip
--	    WHERE ip_end >= ip
--	          and ip_start <= ip and
--	          family = family(ip)
--	    ORDER BY ip_end limit 1;
--
--		RETURN geo_ip_start;
--	END;
--$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION find_geo_ip_start(ip inet)
	RETURNS inet AS $$
	    SELECT ip_start
		    FROM geo_ip
	        WHERE ip_end >= ip
	          and ip_start <= ip and
	          family = family(ip)
	        ORDER BY ip_end limit 1
	$$ LANGUAGE SQL;


-- Table structure for table rpki_validator
DROP TABLE IF EXISTS rpki_validator;
CREATE TABLE rpki_validator (
	prefix              inet            NOT NULL,
	prefix_len          smallint        NOT NULL DEFAULT 0,
	prefix_len_max      smallint        NOT NULL DEFAULT 0,
	origin_as           bigint          NOT NULL,
	timestamp           timestamp       without time zone default (now() at time zone 'utc') NOT NULL,
	PRIMARY KEY (prefix,prefix_len_max,origin_as)
);
CREATE INDEX ON rpki_validator (origin_as);
CREATE INDEX ON rpki_validator USING gist (prefix inet_ops);



-- Table structure for table users
--    note: change password to use crypt(), but change db_rest to support it
--
--    CREATE EXTENSION pgcrypto;
--             Create: crypt('new password', gen_salt('md5'));
--             Check:  select ...  WHERE password = crypt('user entered pw', password);
DROP TABLE IF EXISTS users;
CREATE TABLE users (
	username            varchar(50)     NOT NULL,
	password            varchar(50)     NOT NULL,
	type                user_role       NOT NULL,
	PRIMARY KEY (username)
);
INSERT INTO users (username,password,type) VALUES ('openbmp', 'openbmp', 'admin');


-- Table structure for table collectors
DROP TABLE IF EXISTS collectors;
CREATE TABLE collectors (
	hash_id             uuid                NOT NULL,
	state               opState             DEFAULT 'down',
	admin_id            varchar(64)         NOT NULL,
	routers             varchar(4096),
	router_count        smallint            NOT NULL DEFAULT 0,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	name                varchar(200),
	ip_address          varchar(40),
	PRIMARY KEY (hash_id)
);

-- Table structure for table routers
DROP TABLE IF EXISTS routers;
CREATE TABLE routers (
	hash_id             uuid                NOT NULL,
	name                varchar(200)        NOT NULL,
	ip_address          inet                NOT NULL,
	router_AS           bigint,
	timestamp           timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	description         varchar(255),
	state               opState             DEFAULT 'down',
	isPassive           boolean             DEFAULT false,
	term_reason_code    int,
	term_reason_text    varchar(255),
	term_data           text,
	init_data           text,
	geo_ip_start        inet,
	collector_hash_id   uuid                NOT NULL,
	bgp_id              inet,
	PRIMARY KEY (hash_id)
);


CREATE INDEX ON routers (name);
CREATE INDEX ON routers (ip_address);

-- Table structure for table bgp_peers
DROP TABLE IF EXISTS bgp_peers;
CREATE TABLE bgp_peers (
	hash_id                 uuid                NOT NULL,
	router_hash_id          uuid                NOT NULL,
	peer_rd                 varchar(32)         NOT NULL,
	isIPv4                  boolean             NOT NULL DEFAULT true,
	peer_addr               inet                NOT NULL,
	name                    varchar(200),
	peer_bgp_id             inet                NOT NULL,
	peer_as                 bigint              NOT NULL,
	state                   opState             NOT NULL DEFAULT 'down',
	isL3VPNpeer             boolean             NOT NULL DEFAULT false,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
	isPrePolicy             boolean             DEFAULT true,
	geo_ip_start            inet,
	local_ip                inet,
	local_bgp_id            inet,
	local_port              int,
	local_hold_time         smallint,
	local_asn               bigint,
	remote_port             int,
	remote_hold_time        smallint,
	sent_capabilities       varchar(4096),
	recv_capabilities       varchar(4096),
	bmp_reason              smallint,
	bgp_err_code            smallint,
	bgp_err_subcode         smallint,
	error_text              varchar(255),
	isLocRib                boolean             NOT NULL DEFAULT false,
	isLocRibFiltered        boolean             NOT NULL DEFAULT false,
	table_name              varchar(255),
	PRIMARY KEY (hash_id)
);

CREATE INDEX ON bgp_peers (peer_addr);
CREATE INDEX ON bgp_peers (name);
CREATE INDEX ON bgp_peers (peer_as);
CREATE INDEX ON bgp_peers (router_hash_id);

-- Table structure for table peer_event_log
--     updated by bgp_peers trigger
DROP TABLE IF EXISTS peer_event_log;
CREATE TABLE peer_event_log (
	id                  bigserial               NOT NULL,
	state               opState                 NOT NULL,
	peer_hash_id        uuid                    NOT NULL,
	local_ip            inet,
	local_bgp_id        inet,
	local_port          int,
	local_hold_time     int,
	local_asn           bigint,
	remote_port         int,
	remote_hold_time    int,
	sent_capabilities   varchar(4096),
	recv_capabilities   varchar(4096),
	bmp_reason          smallint,
	bgp_err_code        smallint,
	bgp_err_subcode     smallint,
	error_text          varchar(255),
	timestamp           timestamp(6)            without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON peer_event_log (peer_hash_id);
CREATE INDEX ON peer_event_log (local_ip);
CREATE INDEX ON peer_event_log (local_asn);

-- convert to timescaledb
SELECT create_hypertable('peer_event_log', 'timestamp');


-- Table structure for table stat_reports
--     TimescaleDB
DROP TABLE IF EXISTS stat_reports;
CREATE TABLE stat_reports (
	id                                  bigserial               NOT NULL,
	peer_hash_id                        uuid                    NOT NULL,
	prefixes_rejected                   bigint,
	known_dup_prefixes                  bigint,
	known_dup_withdraws                 bigint,
    updates_invalid_by_cluster_list     bigint,
    updates_invalid_by_as_path_loop     bigint,
    updates_invalid_by_originagtor_id   bigint,
    updates_invalid_by_as_confed_loop   bigint,
    num_routes_adj_rib_in               bigint,
    num_routes_local_rib                bigint,
    timestamp timestamp(6)              without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON stat_reports (peer_hash_id);

-- convert to timescaledb
SELECT create_hypertable('stat_reports', 'timestamp');

-- Table structure for table base_attrs
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/
DROP TABLE IF EXISTS base_attrs;
CREATE TABLE base_attrs (
	hash_id                 uuid                NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin                  varchar(16)         NOT NULL,
	as_path                 varchar(8192)       NOT NULL,
	as_path_count           smallint            DEFAULT 0,
    origin_as               bigint,
    next_hop                inet,
    med                     bigint,
    local_pref              bigint,
    aggregator              varchar(64),
    community_list          varchar(6000),
    ext_community_list      varchar(2048),
    large_community_list    varchar(3000),
    cluster_list            varchar(2048),
    isAtomicAgg             boolean             DEFAULT false,
    nexthop_isIPv4          boolean             DEFAULT true,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    originator_id           inet,
    PRIMARY KEY (hash_id)
);

CREATE INDEX ON base_attrs (origin_as);
CREATE INDEX ON base_attrs (as_path_count);
CREATE INDEX ON base_attrs (as_path);

-- Table structure for table rib
--    https://blog.dbi-services.com/hash-partitioning-in-postgresql-11/--
DROP TABLE IF EXISTS ip_rib;
CREATE TABLE ip_rib (
	hash_id                 uuid                NOT NULL,
    base_attr_hash_id       uuid,
    peer_hash_id            uuid                NOT NULL,
    isIPv4                  boolean             NOT NULL,
    origin_as               bigint,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    first_added_timestamp   timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    isWithdrawn             boolean             NOT NULL DEFAULT false,
    prefix_bits             varchar(128),
    path_id                 bigint,
    labels                  varchar(255),
    isPrePolicy             boolean             NOT NULL DEFAULT true,
    isAdjRibIn              boolean             NOT NULL DEFAULT true,
    PRIMARY KEY (hash_id)
);

-- CREATE UNIQUE INDEX ON ip_rib (hash_id);
CREATE INDEX ON ip_rib (peer_hash_id);
CREATE INDEX ON ip_rib (base_attr_hash_id);
CREATE INDEX ON ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON ip_rib (isWithdrawn);
CREATE INDEX ON ip_rib (origin_as);
CREATE INDEX ON ip_rib (prefix_bits);


-- Table structure for table ip_rib_log
DROP TABLE IF EXISTS ip_rib_log;
CREATE TABLE ip_rib_log (
    id                      bigserial           NOT NULL,
	base_attr_hash_id       uuid                NOT NULL,
	timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    peer_hash_id            uuid                NOT NULL,
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL,
    origin_as               bigint              NOT NULL,
    isWithdrawn             boolean             NOT NULL
) TABLESPACE timeseries;
CREATE INDEX ON ip_rib_log (peer_hash_id);
CREATE INDEX ON ip_rib_log (prefix);
CREATE INDEX ON ip_rib_log (origin_as);

-- convert to timescaledb
SELECT create_hypertable('ip_rib_log', 'timestamp', chunk_time_interval => interval '5 day');


-- Table structure for global ip rib
DROP TABLE IF EXISTS global_ip_rib;
CREATE TABLE global_ip_rib (
    prefix                  inet                NOT NULL,
  	should_delete           boolean             NOT NULL DEFAULT false,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    recv_origin_as          bigint              NOT NULL,
    rpki_origin_as          bigint,
    irr_origin_as           bigint,
    irr_source              varchar(32),
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,

    PRIMARY KEY (prefix,recv_origin_as)
);
CREATE INDEX ON global_ip_rib (recv_origin_as);
CREATE INDEX ON global_ip_rib USING GIST (prefix inet_ops);
CREATE INDEX ON global_ip_rib (should_delete);


-- Table structure for table info_asn (based on whois)
DROP TABLE IF EXISTS info_asn;
CREATE TABLE info_asn (
    asn                     bigint              NOT NULL,
    as_name                 varchar(255),
    org_id                  varchar(255),
    org_name                varchar(255),
    remarks                 text,
    address                 varchar(255),
    city                    varchar(255),
    state_prov              varchar(255),
    postal_code             varchar(255),
    country                 varchar(255),
    raw_output              text,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    source                  varchar(64)         DEFAULT NULL,
    PRIMARY KEY (asn)
);

-- Table structure for table info_route (based on whois)
DROP TABLE IF EXISTS info_route;
CREATE TABLE info_route (
    prefix                  inet                NOT NULL,
    prefix_len              smallint            NOT NULL DEFAULT 0,
    descr                   text,
    origin_as               bigint              NOT NULL,
    source                  varchar(32)         NOT NULL,
    timestamp               timestamp           without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (prefix,prefix_len,origin_as)
);
CREATE INDEX ON info_route (origin_as);


-- Table structure for table as_path_analysis
--     Optionally enabled table to index AS paths
DROP TABLE IF EXISTS as_path_analysis;
CREATE TABLE as_path_analysis (
    asn                     bigint              NOT NULL,
    asn_left                bigint              NOT NULL DEFAULT 0,
    asn_right               bigint              NOT NULL DEFAULT 0,
    asn_left_is_peering     boolean             DEFAULT false,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL,
    PRIMARY KEY (asn,asn_left_is_peering,asn_left,asn_right)
);

CREATE INDEX ON as_path_analysis (asn_left);
CREATE INDEX ON as_path_analysis (asn_right);

-- Alerts table for security monitoring
DROP TABLE IF EXISTS alerts;
CREATE TABLE alerts (
	id                      bigserial           NOT NULL,
    type                    varchar(128)        NOT NULL,
	message                 text                NOT NULL,
    monitored_asn           bigint,
    offending_asn           bigint,
    monitored_asname        varchar(200),
    offending_asname        varchar(200),
	affected_prefix         inet,
	history_url             varchar(512),
	event_json              jsonb,
    timestamp               timestamp(6)        without time zone default (now() at time zone 'utc') NOT NULL
) TABLESPACE timeseries;

CREATE INDEX ON alerts (monitored_asn);
CREATE INDEX ON alerts (offending_asn);
CREATE INDEX ON alerts (type);
CREATE INDEX ON alerts (affected_prefix);

-- convert to timescaledb
SELECT create_hypertable('alerts', 'timestamp');


-- -----------------------------------------------------------------------------------------------
-- Aggregation/stats tables
-- -----------------------------------------------------------------------------------------------

-- advertisement and withdrawal changes by peer
DROP TABLE IF EXISTS stats_chg_bypeer;
CREATE TABLE stats_chg_bypeer (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_chg_bypeer (interval_time,peer_hash_id);
CREATE INDEX ON stats_chg_bypeer (peer_hash_id);

-- convert to timescaledb
SELECT create_hypertable('stats_chg_bypeer', 'interval_time', chunk_time_interval => interval '2 day');

-- advertisement and withdrawal changes by asn
DROP TABLE IF EXISTS stats_chg_byasn;
CREATE TABLE stats_chg_byasn (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	origin_as               bigint              NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_chg_byasn (interval_time,peer_hash_id,origin_as);
CREATE INDEX ON stats_chg_byasn (peer_hash_id);
CREATE INDEX ON stats_chg_byasn (origin_as);

-- convert to timescaledb
SELECT create_hypertable('stats_chg_byasn', 'interval_time', chunk_time_interval => interval '2 day');

-- advertisement and withdrawal changes by prefix
DROP TABLE IF EXISTS stats_chg_byprefix;
CREATE TABLE stats_chg_byprefix (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	prefix                  inet                NOT NULL,
	prefix_len              smallint            NOT NULL,
	updates                 bigint              NOT NULL DEFAULT 0,
	withdraws               bigint              NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_chg_byprefix (interval_time,peer_hash_id,prefix,prefix_len);
CREATE INDEX ON stats_chg_byprefix (peer_hash_id);
CREATE INDEX ON stats_chg_byprefix (prefix,prefix_len);


-- convert to timescaledb
SELECT create_hypertable('stats_chg_byprefix', 'interval_time', chunk_time_interval => interval '2 day');

--
-- Function to update the change stats tables (bypeer, byasn, and byprefix).
--    Will update the tables based on the last 5 minutes, not counting current minute.
--
CREATE OR REPLACE FUNCTION update_chg_stats(int_window interval)
	RETURNS void AS $$
BEGIN
  -- bypeer updates
  INSERT INTO stats_chg_bypeer (interval_time, peer_hash_id, withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 60)::bigint * 60) at time zone 'utc' as IntervalTime,
	       peer_hash_id,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc'    -- current minute
	     GROUP BY IntervalTime,peer_hash_id
	ON CONFLICT (interval_time,peer_hash_id) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

  -- byasn updates
  INSERT INTO stats_chg_byasn (interval_time, peer_hash_id, origin_as,withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 60)::bigint * 60) at time zone 'utc' as IntervalTime,
	       peer_hash_id,origin_as,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 60)::bigint * 60) at time zone 'utc'   -- current minute
	     GROUP BY IntervalTime,peer_hash_id,origin_as
	ON CONFLICT (interval_time,peer_hash_id,origin_as) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

  -- byprefix updates
  INSERT INTO stats_chg_byprefix (interval_time, peer_hash_id, prefix, prefix_len, withdraws,updates)
	SELECT
	       to_timestamp((extract(epoch from timestamp)::bigint / 300)::bigint * 300) at time zone 'utc' as IntervalTime,
	       peer_hash_id,prefix,prefix_len,
	       count(case WHEN ip_rib_log.iswithdrawn = true THEN 1 ELSE null END) as withdraws,
	       count(case WHEN ip_rib_log.iswithdrawn = false THEN 1 ELSE null END) as updates
	     FROM ip_rib_log
	     WHERE timestamp >= to_timestamp((extract(epoch from now())::bigint / 300)::bigint * 300) at time zone 'utc' - int_window
	           AND timestamp < to_timestamp((extract(epoch from now())::bigint / 300)::bigint * 300) at time zone 'utc'   -- current minute
	     GROUP BY IntervalTime,peer_hash_id,prefix,prefix_len
	ON CONFLICT (interval_time,peer_hash_id,prefix,prefix_len) DO UPDATE
		SET updates=excluded.updates, withdraws=excluded.withdraws;

END;
$$ LANGUAGE plpgsql;

-- Origin ASN stats
DROP TABLE IF EXISTS stats_ip_origins;
CREATE TABLE stats_ip_origins (
	id                      bigserial           NOT NULL,
	interval_time           timestamp(6)        without time zone NOT NULL,
	asn                     bigint              NOT NULL,
	v4_prefixes             int                 NOT NULL DEFAULT 0,
	v6_prefixes             int                 NOT NULL DEFAULT 0,
	v4_with_rpki            int                 NOT NULL DEFAULT 0,
	v6_with_rpki            int                 NOT NULL DEFAULT 0,
	v4_with_irr             int                 NOT NULL DEFAULT 0,
	v6_with_irr             int                 NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_ip_origins (interval_time,asn);


-- convert to timescaledb
SELECT create_hypertable('stats_ip_origins', 'interval_time', chunk_time_interval => interval '1 month');

--
-- Function to update the global IP rib and the prefix counts by origin stats. This includes RPKI and IRR counts
--
CREATE OR REPLACE FUNCTION update_global_ip_rib()
	RETURNS void AS $$
BEGIN

	-- mark existing records to be deleted
	UPDATE global_ip_rib SET should_delete = true;

    -- Load the global rib with the current state rib
    INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,timestamp)
        SELECT prefix,prefix_len,origin_as,max(timestamp)
          FROM ip_rib
          WHERE origin_as != 0 AND origin_as != 23456
          GROUP BY prefix,prefix_len,origin_as
      ON CONFLICT (prefix,recv_origin_as)
        DO UPDATE SET should_delete=false;

    -- purge older records marked for deletion and if they are older than 2 hours
    DELETE FROM global_ip_rib where should_delete = true and timestamp < now () - interval '2 hours';

    -- Update IRR
    UPDATE global_ip_rib r SET irr_origin_as=i.origin_as,irr_source=i.source
        FROM info_route i
        WHERE  r.timestamp >= now() - interval '2 hour' and i.prefix = r.prefix;

    -- Update RPKI entries - Limit query to only update what has changed in the last 2 hours
    --    NOTE: The global_ip_rib table should have current times when first run (new table).
    --          This will result in this query taking a while. After first run, it shouldn't take
    --          as long.
     UPDATE global_ip_rib r SET rpki_origin_as=p.origin_as
         FROM rpki_validator p
 		WHERE r.timestamp >= now() - interval '2 hour' AND p.prefix >>= r.prefix AND r.prefix_len >= p.prefix_len and r.prefix_len <= p.prefix_len_max;

     -- Origin stats (originated v4/v6 with IRR and RPKI counts)
     INSERT INTO stats_ip_origins (interval_time,asn,v4_prefixes,v6_prefixes,
               v4_with_rpki,v6_with_rpki,v4_with_irr,v6_with_irr)
       SELECT to_timestamp((extract(epoch from now())::bigint / 3600)::bigint * 3600),
             recv_origin_as,
             sum(case when family(prefix) = 4 THEN 1 ELSE 0 END) as v4_prefixes,
             sum(case when family(prefix) = 6 THEN 1 ELSE 0 END) as v6_prefixes,
             sum(case when rpki_origin_as > 0 and family(prefix) = 4 THEN 1 ELSE 0 END) as v4_with_rpki,
             sum(case when rpki_origin_as > 0 and family(prefix) = 6 THEN 1 ELSE 0 END) as v6_with_rpki,
             sum(case when irr_origin_as > 0 and family(prefix) = 4 THEN 1 ELSE 0 END) as v4_with_irr,
             sum(case when irr_origin_as > 0 and family(prefix) = 6 THEN 1 ELSE 0 END) as v6_with_irr
         FROM global_ip_rib
         GROUP BY recv_origin_as
       ON CONFLICT (interval_time,asn) DO UPDATE SET v4_prefixes=excluded.v4_prefixes,
             v6_prefixes=excluded.v6_prefixes,
             v4_with_rpki=excluded.v4_with_rpki,
             v6_with_rpki=excluded.v6_with_rpki,
             v4_with_irr=excluded.v4_with_irr,
             v6_with_irr=excluded.v6_with_irr;


END;
$$ LANGUAGE plpgsql;


-- Peer rib counts
DROP TABLE IF EXISTS stats_peer_rib;
CREATE TABLE stats_peer_rib (
	interval_time           timestamp(6)        without time zone NOT NULL,
	peer_hash_id            uuid                NOT NULL,
	v4_prefixes             int                 NOT NULL DEFAULT 0,
	v6_prefixes             int                 NOT NULL DEFAULT 0
) TABLESPACE timeseries;

CREATE UNIQUE INDEX ON stats_peer_rib (interval_time,peer_hash_id);
CREATE INDEX ON stats_peer_rib (peer_hash_id);


-- convert to timescaledb
SELECT create_hypertable('stats_peer_rib', 'interval_time', chunk_time_interval => interval '1 month');

--
-- Function to update the per-peer RIB prefix counts
--    This currently is only counting unicast IPv4/Ipv6
--
CREATE OR REPLACE FUNCTION update_peer_rib_counts()
	RETURNS void AS $$
BEGIN
     -- Per peer rib counts - every 15 minutes
     INSERT INTO stats_peer_rib (interval_time,peer_hash_id,v4_prefixes,v6_prefixes)
       SELECT to_timestamp((extract(epoch from now())::bigint / 900)::bigint * 900),
             peer_hash_id,
             sum(CASE WHEN isIPv4 = true THEN 1 ELSE 0 END) AS v4_prefixes,
             sum(CASE WHEN isIPv4 = false THEN 1 ELSE 0 END) as v6_prefixes
         FROM ip_rib
         WHERE isWithdrawn = false
         GROUP BY peer_hash_id
       ON CONFLICT (interval_time,peer_hash_id) DO UPDATE SET v4_prefixes=excluded.v4_prefixes,
             v6_prefixes=excluded.v6_prefixes;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------------------------
-- Utility functions
-- -----------------------------------------------------------------------------------------------

-- Function to display the size of tables
CREATE OR REPLACE FUNCTION show_table_info()
	RETURNS TABLE( oid oid,table_schema name,table_name name,row_estimate real,
				   total_bytes bigint,index_bytes bigint,
	               toast_bytes bigint,table_bytes bigint,total varchar(32),index varchar(32),
	               toast varchar(32),table_value varchar(32)
	              ) AS $$
	    SELECT *, pg_size_pretty(total_bytes) AS total,
                pg_size_pretty(index_bytes) AS INDEX,
                pg_size_pretty(toast_bytes) AS toast,
                pg_size_pretty(table_bytes) AS table_value
		  FROM (
			  SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes FROM (
			      SELECT c.oid,nspname AS table_schema, relname AS TABLE_NAME,
			              c.reltuples AS row_estimate,
			              pg_total_relation_size(c.oid) AS total_bytes,
			              pg_indexes_size(c.oid) AS index_bytes,
			              pg_total_relation_size(reltoastrelid) AS toast_bytes
			          FROM pg_class c
			          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
			          WHERE relkind = 'r'
			  ) a
		) a;
	$$ LANGUAGE SQL;


-- Function to add partitions based on routers index
--    A new partition will be added to each table (currently ip_rib)
--    The routers index check constrain will be updated
CREATE OR REPLACE FUNCTION add_routers_partition()
	RETURNS smallint AS $$
DECLARE
	_parts smallint := 0;
BEGIN

	select count(i.inhrelid) INTO _parts
        from pg_catalog.pg_inherits i
            join pg_catalog.pg_class cl on i.inhparent = cl.oid
            join pg_catalog.pg_namespace nsp on cl.relnamespace = nsp.oid
        where nsp.nspname = 'public'
            and cl.relname = 'ip_rib';

	-- Adjust the max as needed - right now a good default is 500
	IF (_parts < 500) THEN
		_parts := _parts + 1;
		EXECUTE format('CREATE TABLE ip_rib_p%s PARTITION OF ip_rib
		                    FOR VALUES IN (%s)', _parts, _parts);

		EXECUTE format('CREATE UNIQUE INDEX ON ip_rib_p%s (hash_id)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (peer_hash_id)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (base_attr_hash_id)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (prefix)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (isWithdrawn)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (origin_as)', _parts);
		EXECUTE format('CREATE INDEX ON ip_rib_p%s (prefix_bits)', _parts);

		EXECUTE format('ALTER TABLE routers drop constraint routers_index_check, add CONSTRAINT routers_index_check CHECK (index <= %s)', _parts);

		EXECUTE format('DROP TRIGGER IF EXISTS ins_ip_rib_p%s ON ip_rib_p%s',_parts,_parts);

		EXECUTE format('CREATE TRIGGER ins_ip_rib_p%s AFTER INSERT ON ip_rib_p%s FOR EACH ROW EXECUTE PROCEDURE t_ip_rib_insert();',_parts, _parts);

		EXECUTE format('DROP TRIGGER IF EXISTS upd_ip_rib_p%s ON ip_rib_p%s',_parts,_parts);

		EXECUTE format('CREATE TRIGGER upd_ip_rib_p%s BEFORE UPDATE ON ip_rib_p%s FOR EACH ROW EXECUTE PROCEDURE t_ip_rib_update();',_parts, _parts);

	END IF;

	RETURN _parts;
END;
$$ LANGUAGE plpgsql;

-- add partitions
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();
select add_routers_partition();


-- Function to find the next available router index
CREATE OR REPLACE FUNCTION get_next_router_index()
	RETURNS smallint AS $$
DECLARE
	_idx smallint := 0;
	_prev_idx smallint := 0;
BEGIN

	FOR _idx IN SELECT index FROM routers ORDER BY index LOOP
		IF (_prev_idx = 0) THEN
			_prev_idx := _idx;
			CONTINUE;

		ELSIF ( (_prev_idx + 1) != _idx) THEN
			-- Found available index
			RETURN _prev_idx + 1;
		END IF;

		_prev_idx := _idx;
	END LOOP;

	RETURN _prev_idx + 1;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------------------------
-- Triggers and trigger functions for various tables
-- -----------------------------------------------------------------------------------------------

-- =========== Routers =====================
CREATE OR REPLACE FUNCTION t_routers_insert()
	RETURNS trigger AS $$
BEGIN
	SELECT find_geo_ip_start(new.ip_address) INTO new.geo_ip_start;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION t_routers_update()
	RETURNS trigger AS $$
BEGIN
	SELECT find_geo_ip_start(new.ip_address) INTO new.geo_ip_start;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ins_routers ON routers;
CREATE TRIGGER ins_routers BEFORE INSERT ON routers
	FOR EACH ROW
		EXECUTE PROCEDURE t_routers_insert();


DROP TRIGGER IF EXISTS upd_routers ON routers;
CREATE TRIGGER upd_routers BEFORE UPDATE ON routers
	FOR EACH ROW
		EXECUTE PROCEDURE t_routers_update();

-- =========== BGP Peers =====================
CREATE OR REPLACE FUNCTION t_bgp_peers()
	RETURNS trigger AS $$
BEGIN
	IF (new.peer_addr = '0.0.0.0' AND new.peer_bgp_id = '0.0.0.0') THEN
		SELECT r.name,r.ip_address INTO new.name,new.peer_bgp_id
			FROM routers r WHERE r.hash_id = new.router_hash_id;
	END IF;

	SELECT find_geo_ip_start(new.peer_addr) INTO new.geo_ip_start;

	IF (new.state = 'up') THEN
		INSERT INTO peer_event_log (state,peer_hash_id,local_ip,local_bgp_id,local_port,local_hold_time,
                                    local_asn,remote_port,remote_hold_time,
                                    sent_capabilities,recv_capabilities,timestamp)
                VALUES (new.state,new.hash_id,new.local_ip,new.local_bgp_id,new.local_port,new.local_hold_time,
                        new.local_asn,new.remote_port,new.remote_hold_time,
                        new.sent_capabilities,new.recv_capabilities,new.timestamp);
	ELSE
		-- Updated using old values since those are not in the down state
		INSERT INTO peer_event_log (state,peer_hash_id,local_ip,local_bgp_id,local_port,local_hold_time,
                                    local_asn,remote_port,remote_hold_time,
                                    sent_capabilities,recv_capabilities,bmp_reason,bgp_err_code,
                                    bgp_err_subcode,error_text,timestamp)
                VALUES (new.state,new.hash_id,new.local_ip,new.local_bgp_id,new.local_port,new.local_hold_time,
                        new.local_asn,new.remote_port,new.remote_hold_time,
                        new.sent_capabilities,new.recv_capabilities,new.bmp_reason,new.bgp_err_code,
                        new.bgp_err_subcode,new.error_text,new.timestamp);

	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ins_bgp_peers ON bgp_peers;
CREATE TRIGGER ins_bgp_peers BEFORE INSERT ON bgp_peers
	FOR EACH ROW
		EXECUTE PROCEDURE t_bgp_peers();

DROP TRIGGER IF EXISTS upd_bgp_peers ON bgp_peers;
CREATE TRIGGER upd_bgp_peers BEFORE UPDATE ON bgp_peers
	FOR EACH ROW
		EXECUTE PROCEDURE t_bgp_peers();


-- =========== IP RIB =====================
CREATE OR REPLACE FUNCTION t_ip_rib_update()
	RETURNS trigger AS $$
BEGIN
	-- Add record to log table if there is a change
	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
		IF (new.isWithdrawn) THEN
			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
				VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,old.origin_as,new.timestamp);
		ELSE
            IF (old.timestamp < new.timestamp - interval '6 hours') THEN
                SELECT current_timestamp(6) INTO new.first_added_timestamp;
            END IF;

			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
				VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,new.origin_as,new.timestamp);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- not used
CREATE OR REPLACE FUNCTION t_ip_rib_insert()
	RETURNS trigger AS $$
BEGIN

	-- not withdrawn, add record to global table
	IF (not new.isWithdrawn) THEN
		-- Update gen global ip rib  table
		INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,rpki_origin_as,irr_origin_as,irr_source,prefix_bits,isIPv4)

	      SELECT new.prefix,new.prefix_len,new.origin_as,
	             rpki.origin_as, w.origin_as,w.source,new.prefix_bits,new.isIPv4

	      FROM (SELECT new.prefix as prefix, new.prefix_len as prefix_len, new.origin_as as origin_as, new.prefix_bits,
	              new.isIPv4) rib
	        LEFT JOIN info_route w ON (new.prefix = w.prefix AND
	                                        new.prefix_len = w.prefix_len)
	        LEFT JOIN rpki_validator rpki ON (new.prefix = rpki.prefix AND
	                                          new.prefix_len >= rpki.prefix_len and new.prefix_len <= rpki.prefix_len_max)
	      LIMIT 1

	    ON CONFLICT (prefix,prefix_len,recv_origin_as) DO UPDATE SET rpki_origin_as = excluded.rpki_origin_as,
	                  irr_origin_as = excluded.irr_origin_as, irr_source=excluded.irr_source;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- trigger applied on partitions
-- DROP TRIGGER IF EXISTS ins_ip_rib ON ip_rib;
-- CREATE TRIGGER ins_ip_rib AFTER INSERT ON ip_rib
-- 	FOR EACH ROW
-- 		EXECUTE PROCEDURE t_ip_rib_insert();

DROP TRIGGER IF EXISTS upd_ip_rib ON ip_rib;
CREATE TRIGGER upd_ip_rib BEFORE UPDATE ON ip_rib
	FOR EACH ROW
		EXECUTE PROCEDURE t_ip_rib_update();

-- -----------------------------------------------------------------------------------------------
-- Views
-- -----------------------------------------------------------------------------------------------

drop view IF EXISTS v_peers;
CREATE VIEW v_peers AS
SELECT CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE  host(rtr.ip_address) END AS RouterName, rtr.ip_address as RouterIP,
                p.local_ip as LocalIP, p.local_port as LocalPort, p.local_asn as LocalASN, p.local_bgp_id as LocalBGPId,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                p.peer_addr as PeerIP, p.remote_port as PeerPort, p.peer_as as PeerASN,
                p.peer_bgp_id as PeerBGPId,
                p.local_hold_time as LocalHoldTime, p.remote_hold_time as PeerHoldTime,
                p.state as peer_state, rtr.state as router_state,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN, p.isPrePolicy as isPrePolicy,
                p.timestamp as LastModified,
                p.bmp_reason as LastBMPReasonCode, p.bgp_err_code as LastDownCode,
                p.bgp_err_subcode as LastdownSubCode, p.error_text as LastDownMessage,
                p.timestamp as LastDownTimestamp,
                p.sent_capabilities as SentCapabilities, p.recv_capabilities as RecvCapabilities,
                w.as_name,
                p.isLocRib,p.isLocRibFiltered,p.table_name,
                p.hash_id as peer_hash_id, rtr.hash_id as router_hash_id,p.geo_ip_start

        FROM bgp_peers p JOIN routers rtr ON (p.router_hash_id = rtr.hash_id)
                                         LEFT JOIN info_asn w ON (p.peer_as = w.asn);

drop view IF EXISTS v_ip_routes;
CREATE  VIEW v_ip_routes AS
       SELECT  CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
                CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
                r.prefix AS Prefix,r.prefix_len AS PrefixLen,
                attr.origin AS Origin,r.origin_as AS Origin_AS,attr.med AS MED,
                attr.local_pref AS LocalPref,attr.next_hop AS NH,attr.as_path AS AS_Path,
                attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
                attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
                attr.cluster_list AS ClusterList,
                attr.aggregator AS Aggregator,p.peer_addr AS PeerAddress, p.peer_as AS PeerASN,r.isIPv4 as isIPv4,
                p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
                r.timestamp AS LastModified, r.first_added_timestamp as FirstAddedTimestamp,
                r.path_id, r.labels,
                r.hash_id as rib_hash_id,
                r.base_attr_hash_id as base_hash_id, r.peer_hash_id, rtr.hash_id as router_hash_id,r.isWithdrawn,
                r.prefix_bits,r.isPrePolicy,r.isAdjRibIn
        FROM bgp_peers p JOIN ip_rib r ON (r.peer_hash_id = p.hash_id)
            JOIN base_attrs attr ON (attr.hash_id = r.base_attr_hash_id and attr.peer_hash_id = r.peer_hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

drop view IF EXISTS v_ip_routes_history;
CREATE VIEW v_ip_routes_history AS
  SELECT
             CASE WHEN length(rtr.name) > 0 THEN rtr.name ELSE host(rtr.ip_address) END AS RouterName,
            rtr.ip_address as RouterAddress,
	        CASE WHEN length(p.name) > 0 THEN p.name ELSE host(p.peer_addr) END AS PeerName,
            log.prefix AS Prefix,log.prefix_len AS PrefixLen,
            attr.origin AS Origin,log.origin_as AS Origin_AS,
            attr.med AS MED,attr.local_pref AS LocalPref,attr.next_hop AS NH,
            attr.as_path AS AS_Path,attr.as_path_count AS ASPath_Count,attr.community_list AS Communities,
            attr.ext_community_list AS ExtCommunities,attr.large_community_list AS LargeCommunities,
            attr.cluster_list AS ClusterList,attr.aggregator AS Aggregator,p.peer_addr AS PeerIp,
            p.peer_as AS PeerASN,  p.isIPv4 as isPeerIPv4, p.isL3VPNpeer as isPeerVPN,
            log.id,log.timestamp AS LastModified,
            CASE WHEN log.iswithdrawn THEN 'Withdrawn' ELSE 'Advertised' END as event,
            log.base_attr_hash_id as base_attr_hash_id, log.peer_hash_id, rtr.hash_id as router_hash_id
        FROM ip_rib_log log
            JOIN base_attrs attr
                        ON (log.base_attr_hash_id = attr.hash_id AND
                            log.peer_hash_id = attr.peer_hash_id)
            JOIN bgp_peers p ON (log.peer_hash_id = p.hash_id)
            JOIN routers rtr ON (p.router_hash_id = rtr.hash_id);

-- ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
-- NOT DONE YET
--
-- Table structure for table ls_nodes
--
DROP TABLE IF EXISTS ls_nodes;
CREATE TABLE ls_nodes (
  hash_id char(32) NOT NULL,
  peer_hash_id char(32) NOT NULL,
  path_attr_hash_id char(32) NOT NULL,
  id bigint(20) unsigned NOT NULL,
  asn int(10) unsigned NOT NULL,
  bgp_ls_id int(10) unsigned NOT NULL,
  igp_router_id varchar(46) NOT NULL,
  ospf_area_id varchar(16) NOT NULL,
  protocol enum('IS-IS_L1','IS-IS_L2','OSPFv2','Direct','Static','OSPFv3','') DEFAULT NULL,
  router_id varchar(46) NOT NULL,
  isis_area_id varchar(46) NOT NULL,
  flags varchar(20) NOT NULL,
  name varchar(255) NOT NULL,
  isWithdrawn bit(1) NOT NULL DEFAULT b'0',
  timestamp timestamp(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  mt_ids varchar(128) DEFAULT NULL,
  sr_capabilities varchar(255) DEFAULT NULL,
  PRIMARY KEY (hash_id,peer_hash_id),
  KEY idx_router_id (router_id),
  KEY idx_path_attr_hash_id (path_attr_hash_id),
  KEY idx_igp_router_id (igp_router_id),
  KEY idx_peer_id (peer_hash_id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
  PARTITION BY KEY (peer_hash_id);

--
-- Table structure for table ls_links
--
DROP TABLE IF EXISTS ls_links;
CREATE TABLE ls_links (
  hash_id char(32) NOT NULL,
  peer_hash_id char(32) NOT NULL,
  path_attr_hash_id char(32) NOT NULL,
  id bigint(20) unsigned NOT NULL,
  mt_id int(10) unsigned DEFAULT 0,
  interface_addr varchar(46) NOT NULL,
  neighbor_addr varchar(46) NOT NULL,
  isIPv4 tinyint(4) NOT NULL,
  protocol enum('IS-IS_L1','IS-IS_L2','OSPFv2','Direct','Static','OSPFv3','EPE','') DEFAULT NULL,
  local_link_id int(10) unsigned NOT NULL,
  remote_link_id int(10) unsigned NOT NULL,
  local_node_hash_id char(32) NOT NULL,
  remote_node_hash_id char(32) NOT NULL,
  admin_group int(11) NOT NULL,
  max_link_bw int(10) unsigned DEFAULT 0,
  max_resv_bw int(10) unsigned DEFAULT 0,
  unreserved_bw varchar(100) DEFAULT NULL,
  te_def_metric int(10) unsigned NOT NULL,
  protection_type varchar(60) DEFAULT NULL,
  mpls_proto_mask enum('LDP','RSVP-TE','') DEFAULT NULL,
  igp_metric int(10) unsigned NOT NULL,
  srlg varchar(128) NOT NULL,
  name varchar(255) NOT NULL,
  isWithdrawn bit(1) NOT NULL DEFAULT b'0',
  timestamp timestamp(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  local_igp_router_id varchar(46) NOT NULL,
  local_router_id varchar(46) NOT NULL,
  local_asn int(10) unsigned NOT NULL,
  remote_igp_router_id varchar(46) NOT NULL,
  remote_router_id varchar(46) NOT NULL,
  remote_asn int(10) unsigned NOT NULL,
  peer_node_sid varchar(128) NOT NULL,
  sr_adjacency_sids varchar(255) DEFAULT NULL,
  PRIMARY KEY (hash_id,peer_hash_id,local_node_hash_id),
  KEY idx_local_router_id (local_node_hash_id),
  KEY idx_path_attr_hash_id (path_attr_hash_id),
  KEY idx_remote_router_id (remote_node_hash_id),
  KEY idx_peer_id (peer_hash_id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
  PARTITION BY KEY (peer_hash_id);

--
-- Table structure for table ls_prefixes
--
DROP TABLE IF EXISTS ls_prefixes;
CREATE TABLE ls_prefixes (
  hash_id char(32) NOT NULL,
  peer_hash_id char(32) NOT NULL,
  path_attr_hash_id char(32) NOT NULL,
  id bigint(20) unsigned NOT NULL,
  local_node_hash_id char(32) NOT NULL,
  mt_id int(10) unsigned NOT NULL,
  protocol enum('IS-IS_L1','IS-IS_L2','OSPFv2','Direct','Static','OSPFv3','') DEFAULT NULL,
  prefix varchar(46) NOT NULL,
  prefix_len int(8) unsigned NOT NULL,
  prefix_bin varbinary(16) NOT NULL,
  prefix_bcast_bin varbinary(16) NOT NULL,
  ospf_route_type enum('Intra','Inter','Ext-1','Ext-2','NSSA-1','NSSA-2','') DEFAULT NULL,
  igp_flags varchar(20) NOT NULL,
  isIPv4 tinyint(4) NOT NULL,
  route_tag int(10) unsigned DEFAULT NULL,
  ext_route_tag bigint(20) unsigned DEFAULT NULL,
  metric int(10) unsigned NOT NULL,
  ospf_fwd_addr varchar(46) DEFAULT NULL,
  isWithdrawn bit(1) NOT NULL DEFAULT b'0',
  timestamp timestamp(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  sr_prefix_sids varchar(255) DEFAULT NULL,
  PRIMARY KEY (hash_id,peer_hash_id,local_node_hash_id),
  KEY idx_local_router_id (local_node_hash_id),
  KEY idx_path_attr_hash_id (path_attr_hash_id),
  KEY idx_range_prefix_bin (prefix_bcast_bin,prefix_bin)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
  PARTITION BY KEY (peer_hash_id);


--
-- Table structure for table l3vpn_rib
--
DROP TABLE IF EXISTS l3vpn_rib;
CREATE TABLE l3vpn_rib (
  hash_id char(32) NOT NULL,
  path_attr_hash_id char(32) NOT NULL,
  peer_hash_id char(32) NOT NULL,
  isIPv4 tinyint(4) NOT NULL,
  origin_as int(10) unsigned NOT NULL,
  rd varchar(30) NOT NULL,
  prefix varchar(40) NOT NULL,
  prefix_len int(10) unsigned NOT NULL,
  prefix_bin varbinary(16) NOT NULL,
  prefix_bcast_bin varbinary(16) NOT NULL,
  timestamp timestamp(6) NOT NULL DEFAULT current_timestamp(6),
  first_added_timestamp timestamp(6) NOT NULL DEFAULT current_timestamp(6),
  isWithdrawn bit(1) NOT NULL DEFAULT b'0',
  prefix_bits varchar(128) DEFAULT NULL,
  path_id int(10) unsigned DEFAULT NULL,
  labels varchar(255) DEFAULT NULL,
  isPrePolicy tinyint(4) NOT NULL DEFAULT 1,
  isAdjRibIn tinyint(4) NOT NULL DEFAULT 1,
  PRIMARY KEY (hash_id,peer_hash_id,isPrePolicy,isAdjRibIn),
  KEY idx_peer_id (peer_hash_id),
  KEY idx_path_id (path_attr_hash_id),
  KEY idx_prefix (prefix),
  KEY idx_rd (rd),
  KEY idx_prefix_len (prefix_len),
  KEY idx_prefix_bin (prefix_bin),
  KEY idx_addr_type (isIPv4),
  KEY idx_isWithdrawn (isWithdrawn),
  KEY idx_origin_as (origin_as),
  KEY idx_ts (timestamp),
  KEY idx_prefix_bits (prefix_bits),
  KEY idx_first_added_ts (first_added_timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC
  PARTITION BY KEY (peer_hash_id)
  PARTITIONS 48;

DELIMITER ;;
CREATE  TRIGGER l3vpn_rib_pre_update BEFORE UPDATE on l3vpn_rib
FOR EACH ROW
  BEGIN

    IF ( @TRIGGER_DISABLED is null OR @TRIGGER_DISABLED = FALSE ) THEN


      IF (new.hash_id = old.hash_id AND new.peer_hash_id = old.peer_hash_id) THEN
        IF (new.isWithdrawn = False) THEN
          IF (old.path_attr_hash_id != new.path_attr_hash_id AND old.path_attr_hash_id != '') THEN

            INSERT IGNORE INTO l3vpn_log (type,rd,prefix,prefix_len,path_attr_hash_id,peer_hash_id,timestamp)
            VALUES ('changed', old.rd, old.prefix,old.prefix_len,old.path_attr_hash_id,
                    old.peer_hash_id,old.timestamp);
          END IF;


          IF (old.isWithdrawn = True AND old.timestamp < date_sub(new.timestamp, INTERVAL 6 HOUR)) THEN
            SET new.first_added_timestamp = current_timestamp(6);
          END IF;

        ELSE

          INSERT IGNORE INTO l3vpn_log
          (type,rd,prefix,prefix_len,peer_hash_id,path_attr_hash_id,timestamp)
          VALUES ('withdrawn', old.rd, old.prefix,old.prefix_len,old.peer_hash_id,
                  old.path_attr_hash_id,new.timestamp);
        END IF;

      END IF;
    END IF;
  END ;;
DELIMITER ;

--
-- Table structure for table l3vpn_log
--
DROP TABLE IF EXISTS l3vpn_log;
CREATE TABLE l3vpn_log (
  peer_hash_id char(32) NOT NULL,
  type enum('withdrawn','changed') NOT NULL,
  prefix varchar(40) NOT NULL,
  rd varchar(30) NOT NULL,
  prefix_len int(10) unsigned NOT NULL,
  timestamp datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6),
  id bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  path_attr_hash_id char(32) NOT NULL DEFAULT '',
  PRIMARY KEY (id,peer_hash_id,timestamp),
  KEY idx_prefix (prefix,prefix_len),
  KEY idx_rd (rd),
  KEY idx_type (type),
  KEY idx_ts (timestamp),
  KEY idx_peer_hash_id (peer_hash_id)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=latin1 ROW_FORMAT=COMPRESSED KEY_BLOCK_SIZE=8
  PARTITION BY RANGE  COLUMNS(timestamp)
  SUBPARTITION BY KEY (peer_hash_id)
  SUBPARTITIONS 32
  (
  PARTITION p2018_01 VALUES LESS THAN ('2018-02-01') ENGINE = InnoDB,
  PARTITION p2018_02 VALUES LESS THAN ('2018-03-01') ENGINE = InnoDB,
  PARTITION p2018_03 VALUES LESS THAN ('2018-04-01') ENGINE = InnoDB,
  PARTITION p2018_04 VALUES LESS THAN ('2018-05-01') ENGINE = InnoDB,
  PARTITION p2018_05 VALUES LESS THAN ('2018-06-01') ENGINE = InnoDB,
  PARTITION p2018_06 VALUES LESS THAN ('2018-07-01') ENGINE = InnoDB,
  PARTITION p2018_07 VALUES LESS THAN ('2018-08-01') ENGINE = InnoDB,
  PARTITION p2018_08 VALUES LESS THAN ('2018-09-01') ENGINE = InnoDB,
  PARTITION p2018_09 VALUES LESS THAN ('2018-10-01') ENGINE = InnoDB,
  PARTITION p2018_10 VALUES LESS THAN ('2018-11-01') ENGINE = InnoDB,
  PARTITION pOther VALUES LESS THAN (MAXVALUE) ENGINE = InnoDB);

--
-- Table structure for table gen_asn_stats
--
DROP TABLE IF EXISTS gen_asn_stats;
CREATE TABLE gen_asn_stats (
  asn int(10) unsigned NOT NULL,
  isTransit tinyint(4) NOT NULL DEFAULT 0,
  isOrigin tinyint(4) NOT NULL DEFAULT 0,
  transit_v4_prefixes bigint(20) unsigned NOT NULL DEFAULT 0,
  transit_v6_prefixes bigint(20) unsigned NOT NULL DEFAULT 0,
  origin_v4_prefixes bigint(20) unsigned NOT NULL DEFAULT 0,
  origin_v6_prefixes bigint(20) unsigned NOT NULL DEFAULT 0,
  repeats bigint(20) unsigned NOT NULL DEFAULT 0,
  timestamp timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  transit_v4_change decimal(8,5) NOT NULL DEFAULT 0.00000,
  transit_v6_change decimal(8,5) NOT NULL DEFAULT 0.00000,
  origin_v4_change decimal(8,5) NOT NULL DEFAULT 0.00000,
  origin_v6_change decimal(8,5) NOT NULL DEFAULT 0.00000,
  PRIMARY KEY (asn,timestamp)
) ENGINE=InnoDB DEFAULT CHARSET=latin1;

DELIMITER ;;
CREATE TRIGGER ins_gen_asn_stats BEFORE INSERT ON gen_asn_stats
FOR EACH ROW
    BEGIN
        declare last_ts timestamp;
        declare v4_o_count bigint(20) unsigned default 0;
        declare v6_o_count bigint(20) unsigned default 0;
        declare v4_t_count bigint(20) unsigned default 0;
        declare v6_t_count bigint(20) unsigned default 0;
        SET sql_mode = '';
        SELECT transit_v4_prefixes,transit_v6_prefixes,origin_v4_prefixes,
                    origin_v6_prefixes,timestamp
            INTO v4_t_count,v6_t_count,v4_o_count,v6_o_count,last_ts
            FROM gen_asn_stats WHERE asn = new.asn 
            ORDER BY timestamp DESC limit 1;
        IF (new.transit_v4_prefixes = v4_t_count AND new.transit_v6_prefixes = v6_t_count
                AND new.origin_v4_prefixes = v4_o_count AND new.origin_v6_prefixes = v6_o_count) THEN
            set new.timestamp = last_ts;
        ELSE
    IF (v4_t_count > 0 AND new.transit_v4_prefixes > 0 AND new.transit_v4_prefixes != v4_t_count)  THEN
      SET new.transit_v4_change = cast(if(new.transit_v4_prefixes > v4_t_count,
                                   new.transit_v4_prefixes / v4_t_count,
                                   v4_t_count / new.transit_v4_prefixes * -1) as decimal(8,5));
    END IF;
    IF (v6_t_count > 0 AND new.transit_v6_prefixes > 0 AND new.transit_v6_prefixes != v6_t_count) THEN
      SET new.transit_v6_change = cast(if(new.transit_v6_prefixes > v6_t_count,
                                   new.transit_v6_prefixes / v6_t_count,
                                   v6_t_count / new.transit_v6_prefixes * -1) as decimal(8,5));
    END IF;
    IF (v4_o_count > 0 AND new.origin_v4_prefixes > 0 AND new.origin_v4_prefixes != v4_o_count) THEN
      SET new.origin_v4_change = cast(if(new.origin_v4_prefixes > v4_o_count,
                                   new.origin_v4_prefixes / v4_o_count,
                                   v4_o_count / new.origin_v4_prefixes * -1) as decimal(8,5));
    END IF;
    IF (v6_o_count > 0 AND new.origin_v6_prefixes > 0 AND new.origin_v6_prefixes != v6_o_count) THEN
      SET new.origin_v6_change = cast(if(new.origin_v6_prefixes > v6_o_count,
                                   new.origin_v6_prefixes / v6_o_count,
                                   v6_o_count / new.origin_v6_prefixes * -1) as decimal(8,5));
    END IF;
        END IF;
    END ;;
DELIMITER ;

--
-- Table structure for table gen_l3vpn_chg_stats_bypeer
--
DROP TABLE IF EXISTS gen_l3vpn_chg_stats_bypeer;
CREATE TABLE gen_l3vpn_chg_stats_bypeer (
  interval_time datetime(6) NOT NULL,
  peer_hash_id char(32) NOT NULL,
  updates int(10) unsigned NOT NULL DEFAULT 0,
  withdraws int(10) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (interval_time,peer_hash_id),
  KEY idx_interval (interval_time),
  KEY idx_peer_hash_id (peer_hash_id)
) ENGINE=InnoDB DEFAULT CHARSET=latin1
  PARTITION BY RANGE  COLUMNS(interval_time)
  (
  PARTITION p2018_01 VALUES LESS THAN ('2018-02-01') ENGINE = InnoDB,
  PARTITION p2018_02 VALUES LESS THAN ('2018-03-01') ENGINE = InnoDB,
  PARTITION p2018_03 VALUES LESS THAN ('2018-04-01') ENGINE = InnoDB,
  PARTITION p2018_04 VALUES LESS THAN ('2018-05-01') ENGINE = InnoDB,
  PARTITION p2018_05 VALUES LESS THAN ('2018-06-01') ENGINE = InnoDB,
  PARTITION p2018_06 VALUES LESS THAN ('2018-07-01') ENGINE = InnoDB,
  PARTITION p2018_07 VALUES LESS THAN ('2018-08-01') ENGINE = InnoDB,
  PARTITION p2018_08 VALUES LESS THAN ('2018-09-01') ENGINE = InnoDB,
  PARTITION p2018_09 VALUES LESS THAN ('2018-10-01') ENGINE = InnoDB,
  PARTITION p2018_10 VALUES LESS THAN ('2018-11-01') ENGINE = InnoDB,
  PARTITION pOther VALUES LESS THAN (MAXVALUE) ENGINE = InnoDB);

DROP EVENT IF EXISTS chg_l3vpn_stats_bypeer;
DELIMITER ;;
CREATE EVENT chg_l3vpn_stats_bypeer ON SCHEDULE EVERY 5 MINUTE STARTS '2017-10-16 15:21:23' ON COMPLETION NOT PRESERVE ENABLE DO REPLACE INTO gen_l3vpn_chg_stats_bypeer (interval_time, peer_hash_id, updates,withdraws)

  SELECT c.IntervalTime,if (c.peer_hash_id is null, w.peer_hash_id, c.peer_hash_id) as peer_hash_id,
                        if (c.updates is null, 0, c.updates) as updates,
                        if (w.withdraws is null, 0, w.withdraws) as withdraws
  FROM
    (SELECT
                     from_unixtime(unix_timestamp(c.timestamp) - unix_timestamp(c.timestamp) % 60.0) AS IntervalTime,
       peer_hash_id, count(c.peer_hash_id) as updates
     FROM l3vpn_log c
     WHERE c.timestamp >= date_format(date_sub(current_timestamp, INTERVAL 10 MINUTE), "%Y-%m-%d %H:%i:00")
           AND c.timestamp <= date_format(current_timestamp, "%Y-%m-%d %H:%i:00")
           AND type = 'changed'
     GROUP BY IntervalTime,c.peer_hash_id) c

    LEFT JOIN
    (SELECT
                     from_unixtime(unix_timestamp(w.timestamp) - unix_timestamp(w.timestamp) % 60.0) AS IntervalTime,
       peer_hash_id, count(w.peer_hash_id) as withdraws
     FROM l3vpn_log w
     WHERE w.timestamp >= date_format(date_sub(current_timestamp, INTERVAL 25 MINUTE), "%Y-%m-%d %H:%i:00")
           AND w.timestamp <= date_format(current_timestamp, "%Y-%m-%d %H:%i:00")
           AND type = 'withdrawn'
     GROUP BY IntervalTime,w.peer_hash_id) w
      ON (c.IntervalTime = w.IntervalTime AND c.peer_hash_id = w.peer_hash_id);;
DELIMITER ;


--
-- VIEWS
--
drop view IF EXISTS v_geo_ip;
create view v_geo_ip AS
  SELECT inet6_ntoa(ip_start) as ip_start,
         inet6_ntoa(ip_end) as ip_end,
    addr_type, country,stateprov,city,latitude,longitude,timezone_offset,timezone_name,
    isp_name,connection_type,organization_name,ip_start as ip_start_bin,ip_end as ip_end_bin
  FROM geo_ip;

drop view IF EXISTS v_peer_prefix_report_last_id;
create view v_peer_prefix_report_last_id AS
SELECT max(id) as id,peer_hash_id
          FROM stat_reports
          WHERE timestamp >= date_sub(current_timestamp, interval 72 hour)
          GROUP BY peer_hash_id;

drop view IF EXISTS v_peer_prefix_report_last;
create view v_peer_prefix_report_last AS
SELECT if (length(r.name) > 0, r.name, r.ip_address) as RouterName, if (length(p.name) > 0, p.name, p.peer_addr) as PeerName,
                     s.timestamp as TS, prefixes_rejected as Rejected,
                     updates_invalid_by_as_confed_loop AS ConfedLoop, updates_invalid_by_as_path_loop AS ASLoop,
                     updates_invalid_by_cluster_list AS InvalidClusterList, updates_invalid_by_originagtor_id AS InvalidOriginator,
                     known_dup_prefixes AS  KnownPrefix_DUP, known_dup_withdraws AS KnownWithdraw_DUP,
                     num_routes_adj_rib_in as Pre_RIB,num_routes_local_rib as Post_RIB,
                     r.hash_id as router_hash_id, p.hash_id as peer_hash_id

          FROM v_peer_prefix_report_last_id i
                        STRAIGHT_JOIN stat_reports s on (i.id = s.id)
                        STRAIGHT_JOIN bgp_peers p on (s.peer_hash_id = p.hash_id)
                        STRAIGHT_JOIN routers r on (p.router_hash_id = r.hash_id)
          GROUP BY s.peer_hash_id;

drop view IF EXISTS v_peer_prefix_report;
create view v_peer_prefix_report AS
SELECT if (length(r.name) > 0, r.name, r.ip_address) as RouterName, if (length(p.name) > 0, p.name, p.peer_addr) as PeerName,
                     s.timestamp as TS, prefixes_rejected as Rejected,
                     updates_invalid_by_as_confed_loop AS ConfedLoop, updates_invalid_by_as_path_loop AS ASLoop,
                     updates_invalid_by_cluster_list AS InvalidClusterList, updates_invalid_by_originagtor_id AS InvalidOriginator,
                     known_dup_prefixes AS  KnownPrefix_DUP, known_dup_withdraws AS KnownWithdraw_DUP,
                     num_routes_adj_rib_in as Pre_RIB,num_routes_local_rib as Post_RIB,
                     r.hash_id as router_hash_id, p.hash_id as peer_hash_id

          FROM stat_reports s  JOIN  bgp_peers p on (s.peer_hash_id = p.hash_id) join routers r on (p.router_hash_id = r.hash_id)
          order  by s.timestamp desc;


--
-- L3VPN views
--
drop view IF EXISTS v_l3vpn_routes;
CREATE VIEW v_l3vpn_routes AS
	select if((length(rtr.name) > 0),rtr.name,rtr.ip_address) AS RouterName,
	if((length(p.name) > 0),p.name,p.peer_addr) AS PeerName,
 	r.rd AS RD,r.prefix AS Prefix,r.prefix_len AS PrefixLen,path.origin AS Origin,
 	r.origin_as AS Origin_AS,path.med AS MED,path.local_pref AS LocalPref,
 	path.next_hop AS NH,path.as_path AS AS_Path,
	path.as_path_count AS ASPath_Count,path.community_list AS Communities,
	path.ext_community_list AS ExtCommunities,path.large_community_list AS LargeCommunities,
  path.cluster_list AS ClusterList,
	path.aggregator AS Aggregator,p.peer_addr AS PeerAddress,p.peer_as AS PeerASN,
	r.isIPv4 AS isIPv4,p.isIPv4 AS isPeerIPv4,p.isL3VPNpeer AS isPeerVPN,
	r.timestamp AS LastModified,r.first_added_timestamp AS FirstAddedTimestamp,
	r.prefix_bin AS prefix_bin,r.path_id AS path_id,r.labels AS labels,r.hash_id AS rib_hash_id,
	r.path_attr_hash_id AS path_hash_id,r.peer_hash_id AS peer_hash_id,
	rtr.hash_id AS router_hash_id,r.isWithdrawn AS isWithdrawn,
	r.prefix_bits AS prefix_bits,r.isPrePolicy AS isPrePolicy,r.isAdjRibIn AS isAdjRibIn
     from bgp_peers p
               join l3vpn_rib r on (r.peer_hash_id = p.hash_id)
	    join path_attrs path on (path.hash_id = r.path_attr_hash_id and path.peer_hash_id = r.peer_hash_id)
              join routers rtr on (p.router_hash_id = rtr.hash_id)
      where  r.isWithdrawn = 0;

--
-- Link State views
--
drop view IF EXISTS v_ls_nodes;
CREATE VIEW v_ls_nodes AS
SELECT r.name as RouterName,r.ip_address as RouterIP,
       p.name as PeerName, p.peer_addr as PeerIP,igp_router_id as IGP_RouterId,
	ls_nodes.name as NodeName,
         if (ls_nodes.protocol like 'OSPF%', igp_router_id, router_id) as RouterId,
         ls_nodes.id, ls_nodes.bgp_ls_id as bgpls_id, ls_nodes.ospf_area_id as OspfAreaId,
         ls_nodes.isis_area_id as ISISAreaId, ls_nodes.protocol, flags, ls_nodes.timestamp,
         ls_nodes.asn,path_attrs.as_path as AS_Path,path_attrs.local_pref as LocalPref,
         path_attrs.med as MED,path_attrs.next_hop as NH,links.mt_id,
         ls_nodes.hash_id,ls_nodes.path_attr_hash_id,ls_nodes.peer_hash_id,r.hash_id as router_hash_id
      FROM ls_nodes LEFT JOIN path_attrs ON (ls_nodes.path_attr_hash_id = path_attrs.hash_id AND ls_nodes.peer_hash_id = path_attrs.peer_hash_id)
	    JOIN ls_links links ON (ls_nodes.hash_id = links.local_node_hash_id and links.isWithdrawn = False)
            JOIN bgp_peers p on (p.hash_id = ls_nodes.peer_hash_id) JOIN
                             routers r on (p.router_hash_id = r.hash_id)
         WHERE not ls_nodes.igp_router_id regexp "\..[1-9A-F]00$" AND ls_nodes.igp_router_id not like "%]" and ls_nodes.iswithdrawn = False
	GROUP BY ls_nodes.peer_hash_id,ls_nodes.hash_id,links.mt_id;


drop view IF EXISTS v_ls_links;
CREATE VIEW v_ls_links AS
SELECT localn.name as Local_Router_Name,remoten.name as Remote_Router_Name,
         localn.igp_router_id as Local_IGP_RouterId,localn.router_id as Local_RouterId,
         remoten.igp_router_id Remote_IGP_RouterId, remoten.router_id as Remote_RouterId,
         localn.bgp_ls_id as bgpls_id,
         IF (ln.protocol in ('OSPFv2', 'OSPFv3'),localn.ospf_area_id, localn.isis_area_id) as AreaId,
      ln.mt_id as MT_ID,interface_addr as InterfaceIP,neighbor_addr as NeighborIP,
      ln.isIPv4,ln.protocol,igp_metric,local_link_id,remote_link_id,admin_group,max_link_bw,max_resv_bw,
      unreserved_bw,te_def_metric,mpls_proto_mask,srlg,ln.name,ln.timestamp,local_node_hash_id,remote_node_hash_id,
      localn.igp_router_id as localn_igp_router_id_bin,remoten.igp_router_id as remoten_igp_router_id_bin,
      ln.path_attr_hash_id as path_attr_hash_id, ln.peer_hash_id as peer_hash_id
  FROM ls_links ln JOIN ls_nodes localn ON (ln.local_node_hash_id = localn.hash_id
            AND ln.peer_hash_id = localn.peer_hash_id and localn.iswithdrawn = False)
         JOIN ls_nodes remoten ON (ln.remote_node_hash_id = remoten.hash_id
            AND ln.peer_hash_id = remoten.peer_hash_id and remoten.iswithdrawn = False)
	WHERE ln.isWithdrawn = False;


drop view IF EXISTS v_ls_links_new;
CREATE VIEW v_ls_links_new AS
SELECT localn.name as Local_Router_Name,remoten.name as Remote_Router_Name,
         localn.igp_router_id as Local_IGP_RouterId,localn.router_id as Local_RouterId,
         remoten.igp_router_id Remote_IGP_RouterId, remoten.router_id as Remote_RouterId,
         localn.bgp_ls_id as bgpls_id,
         IF (ln.protocol in ('OSPFv2', 'OSPFv3'),localn.ospf_area_id, localn.isis_area_id) as AreaId,
      ln.mt_id as MT_ID,interface_addr as InterfaceIP,neighbor_addr as NeighborIP,
      ln.isIPv4,ln.protocol,igp_metric,local_link_id,remote_link_id,admin_group,max_link_bw,max_resv_bw,
      unreserved_bw,te_def_metric,mpls_proto_mask,srlg,ln.name,ln.timestamp,local_node_hash_id,remote_node_hash_id,
      localn.igp_router_id as localn_igp_router_id_bin,remoten.igp_router_id as remoten_igp_router_id_bin,
      ln.path_attr_hash_id as path_attr_hash_id, ln.peer_hash_id as peer_hash_id,
      if(ln.iswithdrawn, 'INACTIVE', 'ACTIVE') as state
  FROM ls_links ln JOIN ls_nodes localn ON (ln.local_node_hash_id = localn.hash_id
            AND ln.peer_hash_id = localn.peer_hash_id and localn.iswithdrawn = False)
         JOIN ls_nodes remoten ON (ln.remote_node_hash_id = remoten.hash_id
            AND ln.peer_hash_id = remoten.peer_hash_id and remoten.iswithdrawn = False);


drop view IF EXISTS v_ls_prefixes;
CREATE VIEW v_ls_prefixes AS
SELECT localn.name as Local_Router_Name,localn.igp_router_id as Local_IGP_RouterId,
         localn.router_id as Local_RouterId,
         lp.id,lp.mt_id,prefix as Prefix, prefix_len,ospf_route_type,metric,lp.protocol,
         lp.timestamp,lp.prefix_bcast_bin,lp.prefix_bin,
         lp.peer_hash_id
    FROM ls_prefixes lp JOIN ls_nodes localn ON (lp.local_node_hash_id = localn.hash_id)
    WHERE lp.isWithdrawn = False;

--
-- END
--
