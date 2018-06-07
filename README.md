## Hand-crafted host file for use with Samsung Knox Firewall

The aim of this host file has been to keep the amount of hosts as small as possible. Bigger isn't always better, especially with the effective use of wildcards and pruning of dead hosts.

**New**: **2000+** useless dead domains removed.

#### https://raw.githubusercontent.com/mmotti/mmotti-host-file/master/hosts

This host file has been created specifically for use with Samsung Knox Firewall. It is based on the following sources:
* Dan Pollock's host file (http://someonewhocares.org/hosts/hosts)
* pgl@yoyo (https://pgl.yoyo.org/adservers/serverlist.php?hostformat=hosts&showintro=0)
* ZeuS Tracker (https://zeustracker.abuse.ch/blocklist.php?download=domainblocklist)
* Disconnect Tracking (https://s3.amazonaws.com/lists.disconnect.me/simple_tracking.txt)
* Disconnect Ads (https://s3.amazonaws.com/lists.disconnect.me/simple_ad.txt)
* AdGuard Mobile Ads (filterhttps://filters.adtidy.org/extension/chromium/filters/11.txt)

#### Blacklist recommendations
These domains are annoyances that cannot be included in the main host-file due to issues that may arise as a result of blocking them.
* graph.facebook.com (Facebook Ad Choices; can break Facebook login etc.)

#### Whitelist recommendations
These domains may need to be whitelisted for certain sites to function correctly.
* analytics.twitter.com (reports of broken twitter links)

#### Legacy host file ####
This is the original host file. There will be no further updates to this.

https://raw.githubusercontent.com/mmotti/mmotti-host-file/master/wildcard_standard_hosts.txt
