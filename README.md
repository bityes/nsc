# nsc
Network Speed Control
## Des
### List rules
sh auto.sh -list  
### Add one rule
sh auto.sh -add rule -out -port 8080 -max 1024  
sh auto.sh -add rule -in -port 8080 -max 1024  
### Delete one rule
sh auto.sh -del rule -out -id 2  
sh auto.sh -del rule -in -id 2
### Uninstall nsc
sh auto.sh -uninstall  
