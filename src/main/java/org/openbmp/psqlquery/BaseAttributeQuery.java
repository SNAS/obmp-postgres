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

import org.openbmp.api.parsed.message.MsgBusFields;

public class BaseAttributeQuery extends Query{
	
	public BaseAttributeQuery(List<Map<String, Object>> rowMap){
		
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
        final String [] stmt = { " INSERT INTO base_attrs (hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
                                 "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
                                 "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +

                                 "SELECT DISTINCT ON (hash_id) * FROM ( VALUES ",

                                 ") t(hash_id,peer_hash_id,origin,as_path,origin_as,next_hop,med,local_pref," +
                                      "isAtomicAgg,aggregator,community_list,ext_community_list,large_community_list," +
                                      "cluster_list,originator_id,as_path_count,nexthop_isIPv4,timestamp)" +
                                 " ORDER BY hash_id,timestamp desc" +
                                 " ON CONFLICT (hash_id) DO UPDATE SET timestamp=excluded.timestamp " };
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
            sb.append("'" + lookupValue(MsgBusFields.ORIGIN, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.AS_PATH, i) + "',");
            sb.append(lookupValue(MsgBusFields.ORIGIN_AS, i) + ",");
            sb.append("'" + lookupValue(MsgBusFields.NEXTHOP, i) + "'::inet,");
            sb.append(lookupValue(MsgBusFields.MED, i) + ",");
            sb.append(lookupValue(MsgBusFields.LOCAL_PREF, i) + ",");
            sb.append(lookupValue(MsgBusFields.ISATOMICAGG, i) + "::boolean,");
            sb.append("'" + lookupValue(MsgBusFields.AGGREGATOR, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.COMMUNITY_LIST, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.EXT_COMMUNITY_LIST, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.LARGE_COMMUNITY_LIST, i) + "',");
            sb.append("'" + lookupValue(MsgBusFields.CLUSTER_LIST, i) + "',");


            if (((String)lookupValue(MsgBusFields.ORIGINATOR_ID, i)).length() > 0)
                sb.append("'" + lookupValue(MsgBusFields.ORIGINATOR_ID, i) + "'::inet,");
            else
                sb.append("null::inet,");

            sb.append(lookupValue(MsgBusFields.AS_PATH_COUNT, i) + ",");
            sb.append(lookupValue(MsgBusFields.IS_NEXTHOP_IPV4, i) + "::boolean,");
            sb.append("'" + lookupValue(MsgBusFields.TIMESTAMP, i) + "'::timestamp");
            sb.append(')');
        }

        return sb.toString();
    }

    /**
     * Generate MySQL insert/update statement, sans the values for as_path_analysis
     *
     * @return Two strings are returned
     *      0 = Insert statement string up to VALUES keyword
     *      1 = ON DUPLICATE KEY UPDATE ...  or empty if not used.
     */
    public String[] genAsPathAnalysisStatement() {
        final String [] stmt = {" INSERT INTO as_path_analysis (asn,asn_left,asn_right,asn_left_is_peering)" +
                                    " VALUES ",
                                " ON CONFLICT (asn,asn_left_is_peering,asn_left,asn_right) DO NOTHING" };
        return stmt;
    }

    /**
     * Generate bulk values statement for SQL bulk insert for as_path_analysis
     *
     * @return String in the format of (col1, col2, ...)[,...]
     */
    public String genAsPathAnalysisValuesStatement() {
        StringBuilder sb = new StringBuilder();
        Set<String> values = new HashSet<String>();

        /*
         * Iterate through the AS Path and extract out the left and right ASN for each AS within
         *     the AS PATH
         */
        for (int i=0; i < rowMap.size(); i++) {

            String as_path_str = ((String)lookupValue(MsgBusFields.AS_PATH, i)).trim();
            as_path_str = as_path_str.replaceAll("[{}]", "");
            String[] as_path = as_path_str.split(" ");

            Long left_asn = 0L;
            Long right_asn = 0L;
            Long asn = 0L;

            for (int i2=0; i2 < as_path.length; i2++) {
                if (as_path[i2].length() <= 0)
                    break;

                try {
                    asn = Long.valueOf(as_path[i2]);
                } catch (NumberFormatException e) {
                    e.printStackTrace();
                    break;
                }

                if (asn > 0 ) {
                    if (i2+1 < as_path.length) {

                        if (as_path[i2 + 1].length() <= 0)
                            break;

                        try {
                            right_asn = Long.valueOf(as_path[i2 + 1]);

                        } catch (NumberFormatException e) {
                            e.printStackTrace();
                            break;
                        }

                        if (right_asn.equals(asn)) {
                            continue;
                        }

                        String isPeeringAsn = (i2 == 0 || i2 == 1) ? "1" : "0";
                        values.add("(" + asn + "," + left_asn + "," + right_asn + "," + isPeeringAsn + "::boolean)");


                    } else {
                        // No more left in path - Origin ASN
                          values.add("(" + asn + "," + left_asn + ",0,false)");
                        break;
                    }

                    left_asn = asn;
                }
            }
        }


        for (String value: values) {
            if (sb.length() > 0) {
                sb.append(',');
            }

            sb.append(value);
        }

        return sb.toString();
    }

}
