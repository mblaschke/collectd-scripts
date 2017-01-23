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
        # Freifunk
	Exec nobody "/opt/collectd/freifunk/collectd.sh" "60e327f23138" "687251345b9b" "687251303cfa" "6872513223a9" "c4e9847db5a6" "a42bb0cdad35" "687251608192"
</Plugin>
```
