## MMotti Host File (Samsung Knox Firewall)
### Now serving as the default host provider for Adhell3

The aim of this host file has been to keep the amount of hosts as small as possible. Bigger isn't always better, especially with the effective use of wildcards and pruning of dead hosts.

**https://raw.githubusercontent.com/mmotti/mmotti-host-file/master/hosts**

This host file has been created specifically for use with Samsung Knox Firewall; It is based on the following sources:

* http://someonewhocares.org/hosts/hosts
* https://filters.adtidy.org/extension/chromium/filters/11.txt
* https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0
* https://raw.githubusercontent.com/hoshsadiq/adblock-nocoin-list/master/hosts.txt
* https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt
* https://s3.amazonaws.com/lists.disconnect.me/simple_malvertising.txt
* https://s3.amazonaws.com/lists.disconnect.me/simple_malware.txt
* https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt
* https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist

#### Blacklist recommendations
These domains are annoyances that cannot be included in the main host-file due to issues that may arise as a result of blocking them.
* **graph.facebook.com** (Facebook Ad Choices; can break Facebook login etc.)

#### Whitelist recommendations
These domains may need to be whitelisted for certain sites to function correctly.
* **analytics.twitter.com** (reports of broken twitter links)