-- -----------------------------------------------------------------------
-- Copyright (c) 2018 Cisco Systems, Inc. and others.  All rights reserved.
-- Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
--
-- BEGIN Triggers
-- -----------------------------------------------------------------------

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
	-- Only update
	-- Add record to log table if there is a change
	IF ((new.isWithdrawn <> old.isWithdrawn) OR (not new.isWithdrawn AND new.base_attr_hash_id <> old.base_attr_hash_id)) THEN
		IF (new.isWithdrawn) THEN
			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
				VALUES (true,new.prefix,new.prefix_len,old.base_attr_hash_id,new.peer_hash_id,old.origin_as,new.timestamp);
		ELSE
			-- Update first added to DB when prefix has been withdrawn for too long
            IF (old.isWithdrawn AND old.timestamp < (new.timestamp - interval '6 hours')) THEN
                SELECT current_timestamp(6) INTO new.first_added_timestamp;
            END IF;

			INSERT INTO ip_rib_log (isWithdrawn,prefix,prefix_len,base_attr_hash_id,peer_hash_id,origin_as,timestamp)
				VALUES (false,new.prefix,new.prefix_len,new.base_attr_hash_id,new.peer_hash_id,new.origin_as,new.timestamp);
		END IF;
	END IF;

	RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ** not used **
-- CREATE OR REPLACE FUNCTION t_ip_rib_insert()
-- 	RETURNS trigger AS $$
-- BEGIN
--
-- 	-- not withdrawn, add record to global table
-- 	IF (not new.isWithdrawn) THEN
-- 		-- Update gen global ip rib  table
-- 		INSERT INTO global_ip_rib (prefix,prefix_len,recv_origin_as,rpki_origin_as,irr_origin_as,irr_source,prefix_bits,isIPv4)
--
-- 	      SELECT new.prefix,new.prefix_len,new.origin_as,
-- 	             rpki.origin_as, w.origin_as,w.source,new.prefix_bits,new.isIPv4
--
-- 	      FROM (SELECT new.prefix as prefix, new.prefix_len as prefix_len, new.origin_as as origin_as, new.prefix_bits,
-- 	              new.isIPv4) rib
-- 	        LEFT JOIN info_route w ON (new.prefix = w.prefix AND
-- 	                                        new.prefix_len = w.prefix_len)
-- 	        LEFT JOIN rpki_validator rpki ON (new.prefix = rpki.prefix AND
-- 	                                          new.prefix_len >= rpki.prefix_len and new.prefix_len <= rpki.prefix_len_max)
-- 	      LIMIT 1
--
-- 	    ON CONFLICT (prefix,prefix_len,recv_origin_as) DO UPDATE SET rpki_origin_as = excluded.rpki_origin_as,
-- 	                  irr_origin_as = excluded.irr_origin_as, irr_source=excluded.irr_source;
-- 	END IF;
--
-- 	RETURN NEW;
-- END;
-- $$ LANGUAGE plpgsql;

-- trigger applied on partitions
-- DROP TRIGGER IF EXISTS ins_ip_rib ON ip_rib;
-- CREATE TRIGGER ins_ip_rib AFTER INSERT ON ip_rib
-- 	FOR EACH ROW
-- 		EXECUTE PROCEDURE t_ip_rib_insert();

DROP TRIGGER IF EXISTS upd_ip_rib ON ip_rib;
CREATE TRIGGER upd_ip_rib BEFORE UPDATE ON ip_rib
	FOR EACH ROW
		EXECUTE PROCEDURE t_ip_rib_update();


--
-- END
--
