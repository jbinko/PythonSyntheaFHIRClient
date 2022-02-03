#/bin/bash
crontab -l > temp.crontab
echo "@reboot $1 $2" >> temp.crontab
crontab -u vmadmin temp.crontab
rm temp.crontab
echo "Successfully updated cron"
