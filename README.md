# meshtastic_scripts
Scripts for meshtastic

This repo is for simple scripts to make meshtastic more fun for you and other connected nodes

Starting the repo with a weather script.  It runs on a cron job, gets the most recent weather forecast and posts it to the mesh as scheduled in the cron.



E.g.
58 7,19 * * * /bin/bash /home/XXX/meshweather.sh >> /home/XXX/logs/meshweather-cron.log 2>&1
0 0 * * 0 > /home/XXX/logs/meshweather-cron.log

#10 20 * * * /bin/bash /home/XXX/nightly_check.sh >> /home/XXX/meshtastic_logs/cron_output.log 2>&1
*/10 * * * * /bin/bash /home/XXX/meshtastic_responder.sh

0,30 * * * * /bin/bash /home/XXX/meshweather_alerts.sh >> /home/XXX/logs/meshweather_alerts-cron.log 2>&1

