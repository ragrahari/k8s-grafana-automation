#!/bin/bash
# Input dashboard name
if [ "$#" -ne 1 ]; then
    echo "Usage:"
    echo "  $0 dashboard_name"
	echo "example: ./update_dashboard.sh k8s-pods-summary"
	sleep 1 
    exit 1
fi

# Strip the extension from input argument, if any
dashb_input=$( echo "${1%.*}" )
dashboard=${dashb_input}.json

cd ./dashboards
dash_content=$(jq -c . < ${dashboard})
if [[ $dash_content != *"{\"dashboard\""* ]]; then
	echo "Adding dashboard tag to the json"
	cp ${dashboard} ${dashboard}.bak
	sed '1i{ \"dashboard\": ' ${dashboard}.bak > ${dashboard}
	echo '}' >> ${dashboard}
fi

grafana_host="https://$( oc get route grafana -n grafana -o jsonpath='{.spec.host}' )"

dashb_to_update="./${dashboard}"
dashb_to_delete=$( echo "${dashb_input//-}" )
# Delete the existing dashboard
printf "\nDeleting existing dashboard"
echo $dashb_to_delete
curl --insecure -H "Content-Type: application/json" -H "Authorization: 'Bearer $( oc sa get-token prometheus-k8s -n openshift-monitoring )'" "${grafana_host}/api/dashboards/uid/${dashb_to_delete}" -X DELETE
# Create the new dashboard
printf "\nCreating latest dashboard"
curl --insecure -H "Content-Type: application/json" -H "Authorization: 'Bearer $( oc sa get-token prometheus-k8s -n openshift-monitoring )'" "${grafana_host}/api/dashboards/db" -X POST -d "@${dashb_to_update}"

if [[ $dash_content != *"{\"dashboard\""* ]]; then
	rm ${dashboard}.bak
fi

printf "\nScript completed!"
