#!/bin/bash
# Default values of arguments:
datasource_name='prometheus'
prometheus_namespace='openshift-monitoring'
sa_reader='prometheus-k8s'
protocol="https://"

while getopts 'n:s:p' flag; do
  case "${flag}" in
    n) datasource_name="${OPTARG}" ;;
    s) sa_reader="${OPTARG}" ;;
    p) prometheus_namespace="${OPTARG}" ;;
    *) error "Unexpected option ${flag}" ;;
  esac
done

usage() {
echo "
USAGE
 setup-grafana.sh -n <datasource_name> -a [optional: -p <prometheus_namespace> -s <prometheus_serviceaccount> -g <graph_granularity> -y <yaml> -e]

 switches:
   -n: grafana datasource name
   -s: prometheus serviceaccount name
   -p: existing prometheus name e.g openshift-monitoring

 note:
    - the project must have view permissions for kube-system
    - the script allow to use high granularity by adding '30s' arg, but it needs tuned scrape prometheus
"
exit 1
}

prometheus_namespace="openshift-monitoring"
sa_reader="prometheus-k8s"
yaml="grafana.yaml"

oc new-project grafana
oc process -f "${yaml}" |oc create -f -
oc rollout status deployment/grafana
sleep 2s
oc adm policy add-role-to-user view -z grafana -n "${prometheus_namespace}"

authUser="$(oc get secret grafana-datasources -n openshift-monitoring -o yaml | grep prometheus.yaml | sed 's/  prometheus.yaml: //' | base64 -d | grep basicAuthUser | sed 's/            "basicAuthUser": "//' | sed 's/",//')"
authPassword="$(oc get secret grafana-datasources -n openshift-monitoring -o yaml | grep prometheus.yaml | sed 's/  prometheus.yaml: //' | base64 -d | grep basicAuthPassword | sed 's/            "basicAuthPassword": "//' | sed 's/",//')"

payload="$( mktemp )"
cat <<EOF >"${payload}"
{
"name": "${datasource_name}",
"type": "prometheus",
"typeLogoUrl": "",
"access": "proxy",
"url": "https://$( oc get route prometheus-k8s -n "${prometheus_namespace}" -o jsonpath='{.spec.host}' )",
"basicAuth": true,
"basicAuthPassword": "$authPassword",
"basicAuthUser": "$authUser",
"withCredentials": false,
"jsonData": {
    "tlsSkipVerify":true
},
"secureJsonData": {
    "httpHeaderValue1":"Bearer $( oc sa get-token "${sa_reader}" -n "${prometheus_namespace}" )"
}
}
EOF

# setup grafana data source
grafana_host="${protocol}$( oc get route grafana -o jsonpath='{.spec.host}' )"

printf "sleep 5 seconds for grafana to load up before adding datasource\n"
sleep 5s
# Add prometheus datasource
curl --insecure -H "Content-Type: application/json" "${grafana_host}/api/datasources" -X POST -d "@${payload}"

# deploy all dashboards from dashboards directory
all_dashb=$( ls ./dashboards/*.json )
for dashb_to_create in $all_dashb
do
  printf "\nCreating dashboard: $dashb_to_create\n"
	curl --insecure -H "Content-Type: application/json" -H "Authorization: 'Bearer $( oc sa get-token prometheus-k8s -n openshift-monitoring )'" "${grafana_host}/api/dashboards/db" -X POST -d "@${dashb_to_create}"
done

printf "\nSetup complete!\n"
exit 0
