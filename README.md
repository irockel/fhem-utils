# fhem-utils

Collection of utils I use with home automation software [fhem](http://www.fhem.de). 

* **99_SMAUtils.pm** - patched version of Module for fetching data from Solar Inverters by SMA, this version avoids the error about the unknown parameter *delay* and fixes the available readings attributes, so "event-on-change-reading" is possible and allows to reduce the events send by the module. For further details on configuration of the module, consult the [fhem Wiki](https://wiki.fhem.de/wiki/SMAWechselrichter).
