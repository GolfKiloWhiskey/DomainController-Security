  #Used to gather hash table data for Event ID's, really menat to build out lnegthy scripts to troubleshoot specififc event ID issues. 
#Refer here for additional info:
#https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-erref/596a1078-e883-4972-9bbc-49e60bebca55
#https://learn.microsoft.com/en-us/windows/security/threat-protection/auditing/security-auditing-overview

$events = Get-WinEvent -FilterHashtable @{LogName='Security'; ID=4625} -MaxEvents 1
$eventXml = [xml]$events.ToXml()
$eventData = $eventXml.Event.EventData.Data
$eventdata