#!/bin/bash

# set -x

function setK8sContext () {

    local LOCAL_GOOGLE_PROJECT=$1
    local LOCAL_GOOGLE_ZONE=$2
    local LOCAL_CLUSTER_NAME=$3

    gcloud --project $LOCAL_GOOGLE_PROJECT container clusters get-credentials $LOCAL_CLUSTER_NAME --zone $LOCAL_GOOGLE_ZONE
    fish -c 'set -xU K8S_CLUSTER (kubectl config current-context)'
    fish -c 'set -xU K8S_CLUSTER_SHORT (kubectl config current-context | cut -d "_" -f 4)'
    fish -c 'set -xU K8S_CLUSTER_VERSION (kubectl version --short | awk "/Server/{print\$3}")'
    fish -c 'set -U fish_prompt_detailed_reset 1'
}

function unsetK8sContext () {
    kubectl config unset current-context
    fish -c 'set -xU K8S_CLUSTER (kubectl config current-context 2>&1)'
    fish -c 'set -xU K8S_CLUSTER_SHORT "n/a"'
    fish -c 'set -xU K8S_CLUSTER_VERSION "n/a"'
}

GCP_CONFIGS=$(gcloud config configurations list --format="value(name)") 

GCP_CURRENT_CONFIG=$(gcloud config configurations list --filter 'is_active=true' --format 'value(name)')

if [ -z "$GCP_CONFIGS" ]; then
    echo "You don't have any gcloud configurations."
else
    if [ -z $1 ]; then
        echo "Please add configuration name."
        echo "Your configurations:"
        echo "$GPC_CONFIGS"
    else
        case $1 in 
            "list")
                printf "Your configs:\n$GCP_CONFIGS"
                ;;
            "reset")
                VALID_CONFIG=true
                SET_PROJECT=true
                SELECTED_CONFIGURATION=$GCP_CURRENT_CONFIG
                ;;
            "$GCP_CURRENT_CONFIG")
                echo "$1 is the current config. "
                if [ ! -z $2 ]; then
                    if [ $2 == $K8S_CLUSTER_SHORT ]; then
                        echo "$2 is the current cluster."
                    else
                        SET_PROJECT=true
                        for CLUSTER in $(gcloud container clusters list --format='value(name)'); do
                            if [ $CLUSTER == $2 ]; then
                                VALID_CLUSTER=true
                            fi
                        done
                    fi
                fi
                VALID_CONFIG=true
                ;;
             *)
                for CFG in $GCP_CONFIGS; do
                    if [ $CFG == $1 ]; then
                        VALID_CONFIG=true
                        SET_PROJECT=true
                        CLEAR_CREDENTIALS=true
                        SELECTED_CONFIGURATION=$1
                        break
                    fi
                done
                ;;
        esac

        if [ $VALID_CONFIG ]; then 

            fish -c 'set -U fish_detailed_prompt_reset 1'

            if [ $SET_PROJECT ]; then

                if [ $CLEAR_CREDENTIALS ]; then
                    fish -c 'set -eU GOOGLE_APPLICATION_CREDENTIALS'
                fi
                gcloud config configurations activate $SELECTED_CONFIGURATION
                fish -c 'set -xU GOOGLE_CONFIG (gcloud config configurations list --filter "is_active=true" --format="value(name)")'

                # this is required because variable export through fish is not available later
                GOOGLE_PROJECT=$(gcloud config list --format="value(core.project)")
                fish -c 'set -xU GOOGLE_PROJECT (gcloud config list --format="value(core.project)")'
                GOOGLE_REGION=$(gcloud config list --format="value(compute.region)")
                fish -c 'set -xU GOOGLE_REGION (gcloud config list --format="value(compute.region)")'
                GOOGLE_ZONE=$(gcloud config list --format="value(compute.zone)")
                fish -c 'set -xU GOOGLE_ZONE (gcloud config list --format="value(compute.zone)")'

                # check cluster in configuration    
                CLUSTER_IN_CONFIGURATION=$(gcloud config list --format="value(container.cluster)")

                if [ -z "$CLUSTER_IN_CONFIGURATION" ]; then
                    echo "Cluster is not specified in selected [$SELECTED_CONFIGURATION] configuration."
                    echo "Looking for running cluster in [$GOOGLE_ZONE]..."

                    CLUSTER=$(gcloud container clusters list --zone $GOOGLE_ZONE --format='value(name)')
                    
                    if [ -z $CLUSTER ]; then
                        echo "This zone [$GOOGLE_ZONE] in $GOOGLE_PROJECT does not have any running clusters."
                        RUNNING_CLUSTERS=($(gcloud container clusters list --filter status=RUNNING --format="value(name)"))
                        if [ -z "$RUNNING_CLUSTERS" ]; then
                            echo "$GOOGLE_PROJECT project does not have any running clusters."
                        else
                            if [ "${#RUNNING_CLUSTERS[@]}" -ge 1 ]; then
                                echo -e "But $GOOGLE_PROJECT has clusters. Check the list below and try one of them.\n"
                                gcloud container clusters list
                            fi
                        fi
                        unsetK8sContext
                    else
                        setK8sContext $GOOGLE_PROJECT $GOOGLE_ZONE $CLUSTER
                    fi
                else
                    # check cluster is running 
                    if [[ $(gcloud container clusters list --filter "name=$CLUSTER_IN_CONFIGURATION" --format="value(status)") == "RUNNING" ]]; then
                        echo "Cluster [$CLUSTER_IN_CONFIGURATION] is running. Use for kubectl"
                        setK8sContext $GOOGLE_PROJECT $GOOGLE_ZONE $CLUSTER_IN_CONFIGURATION
                    else
                        echo "This cluster [$CLUSTER_IN_CONFIGURATION] from [$GOOGLE_PROJECT] project is not available in [$GOOGLE_ZONE] zone. kubectl context unset."
                        unsetK8sContext
                    fi
                fi
            fi
        fi
    fi
fi
