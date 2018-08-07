/*
 * Copyright (c) 2018 Tim Evens (tim@evensweb.com).  All rights reserved.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Eclipse Public License v1.0 which accompanies this distribution,
 * and is available at http://www.eclipse.org/legal/epl-v10.html
 *
 */
package org.openbmp.psqlquery;

import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.openbmp.RouterObject;
import org.openbmp.api.helpers.IpAddr;
import org.openbmp.api.parsed.message.MsgBusFields;



public class UnicastPrefixQuery extends Query{

	public UnicastPrefixQuery(List<Map<String, Object>> rowMap){
		
		this.rowMap = rowMap;
	}
	
	
    /**
     * Generate MySQL insert/update statement, sans the values
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genInsertStatement() {
        String [] stmt = { " INSERT INTO ip_rib (hash_id,peer_hash_id,base_attr_hash_id,isIPv4," +
                           "origin_as,prefix,prefix_len,prefix_bits,timestamp," +
                           "isWithdrawn,path_id,labels,isPrePolicy,isAdjRibIn) " +

                            "SELECT DISTINCT ON (hash_id) * FROM ( VALUES ",

                            ") t(hash_id,peer_hash_id,base_attr_hash_id,isIPv4," +
                                "origin_as,prefix,prefix_len,prefix_bits,timestamp,"  +
                                "isWithdrawn,path_id,labels,isPrePolicy,isAdjRibIn) " +
                           " ORDER BY hash_id,timestamp desc" +

                           " ON CONFLICT (hash_id) DO UPDATE SET timestamp=excluded.timestamp," +
                               "base_attr_hash_id=CASE excluded.isWithdrawn WHEN true THEN ip_rib.base_attr_hash_id ELSE excluded.base_attr_hash_id END," +
                               "origin_as=CASE excluded.isWithdrawn WHEN true THEN ip_rib.origin_as ELSE excluded.origin_as END," +
                               "isWithdrawn=excluded.isWithdrawn," +
                               "path_id=excluded.path_id, labels=excluded.labels," +
                               "isPrePolicy=excluded.isPrePolicy, isAdjRibIn=excluded.isAdjRibIn "
                        };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert.
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genValuesStatement() {
        StringBuilder sb = new StringBuilder();

        for (int i=0; i < rowMap.size(); i++) {

            if (i > 0)
                sb.append(',');

            sb.append('(');
            sb.append("'" + lookupValue(MsgBusFields.HASH, i) + "'::uuid,");
            sb.append("'" + lookupValue(MsgBusFields.PEER_HASH, i) + "'::uuid,");

            if ( ((String)lookupValue(MsgBusFields.BASE_ATTR_HASH, i)).length() >= 32)
                sb.append("'" + lookupValue(MsgBusFields.BASE_ATTR_HASH, i) + "'::uuid,");
            else
                sb.append("null::uuid,");

            sb.append(lookupValue(MsgBusFields.IS_IPV4, i) + "::boolean,");

            sb.append(lookupValue(MsgBusFields.ORIGIN_AS, i) + ",");

            //sb.append("'" + lookupValue(MsgBusFields.PREFIX, i) + "'::inet,");
            sb.append("'" + lookupValue(MsgBusFields.PREFIX, i) + "/");
            sb.append(lookupValue(MsgBusFields.PREFIX_LEN, i));
            sb.append("'::inet,");

            sb.append(lookupValue(MsgBusFields.PREFIX_LEN, i) + ",");

            try {
                sb.append("'" + IpAddr.getIpBits((String) lookupValue(MsgBusFields.PREFIX, i)).substring(0, (Integer) lookupValue(MsgBusFields.PREFIX_LEN, i)) + "',");
            } catch (StringIndexOutOfBoundsException e) {

                //TODO: Fix getIpBits to support mapped IPv4 addresses in IPv6 (::ffff:ipv4)
                System.out.println("IP prefix failed to convert to bits: " +
                        (String) lookupValue(MsgBusFields.PREFIX, i) + " len: " + (Integer) lookupValue(MsgBusFields.PREFIX_LEN, i));
                sb.append("'',");
            }

            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i) + "'::timestamp,");
            sb.append((((String)lookupValue(MsgBusFields.ACTION, i)).equalsIgnoreCase("del") ? "true" : "false") + ",");
            sb.append(lookupValue(MsgBusFields.PATH_ID, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.LABELS, i) + "',");
            sb.append(lookupValue(MsgBusFields.ISPREPOLICY, i) + "::boolean,");
            sb.append(lookupValue(MsgBusFields.IS_ADJ_RIB_IN, i) + "::boolean");

            sb.append(')');
        }

        return sb.toString();
    }

}
