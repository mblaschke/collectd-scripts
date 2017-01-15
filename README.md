Collectd scripts
================

Configuration for collectd
--------------------------

```
<Plugin exec>
        # Synology
        Interval 60
        Exec nobody "/opt/collectd/synology/collectd.sh"  "diskstation"
</Plugin>

<Plugin exec>
        # Update
        Interval 300

        # Update
	Exec nobody "/opt/collectd/freifunk/collectd.sh" "update"

        # BB Feldbergstr
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "60e327f23138"
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "687251345b9b"
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "687251303cfa"
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "687251608192"
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "6872513223a9"

        # Bayreuth
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "c4e9847db5a6"

        # LUGBB demo
        Exec nobody "/opt/collectd/freifunk/collectd.sh" "a42bb0cdad35"
</Plugin>
```
