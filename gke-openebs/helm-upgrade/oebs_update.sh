#!/bin/bash -x

################################################################
# STEP: Get Persistent Volume (PV) name as argument            #
#                                                              #
# NOTES: Obtain the pv to upgrade via "kubectl get pv"         #
################################################################

pv=$1
ns=$2

################################################################ 
# STEP: Generate deploy, replicaset and container names from PV#
#                                                              #
# NOTES: Ex: If PV="pvc-cec8e86d-0bcc-11e8-be1c-000c298ff5fc", #
#                                                              #
# ctrl-dep: pvc-cec8e86d-0bcc-11e8-be1c-000c298ff5fc-ctrl      #  
# ctrl-cont: pvc-cec8e86d-0bcc-11e8-be1c-000c298ff5fc-ctrl-con #  
################################################################

c_dep=$(echo $pv-ctrl); c_name=$(echo $c_dep-con)
r_dep=$(echo $pv-rep); r_name=$(echo $r_dep-con)

c_rs=$(kubectl get rs -o name --namespace $ns | grep $c_dep | cut -d '/' -f 2)
r_rs=$(kubectl get rs -o name --namespace $ns | grep $r_dep | cut -d '/' -f 2)

################################################################ 
# STEP: Update patch files with appropriate container names    #
#                                                              # 
# NOTES: Placeholder "pvc-<deploy-hash>-ctrl/rep-con in the    #
# patch files are replaced with container names derived from   #
# the PV in the previous step                                  #  
################################################################

sed "s/pvc[^ \"]*/$r_name/g" replica.patch.tpl.yml > replica.patch.yml
sed "s/pvc[^ \"]*/$c_name/g" controller.patch.tpl.yml > controller.patch.yml

################################################################
# STEP: Patch OpenEBS volume deployments (controller, replica) #  
#                                                              #
# NOTES: Strategic merge patch is used to update the volume w/ #  
# rollout status verification                                  #  
################################################################

# PATCH JIVA REPLICA DEPLOYMENT ####
kubectl patch deployment --namespace $ns $r_dep -p "$(cat replica.patch.yml)"
rc=$?; if [ $rc -ne 0 ]; then echo "ERROR: $rc"; exit; fi

rollout_status=$(kubectl rollout status --namespace $ns deployment/$r_dep)
rc=$?; if [[ ($rc -ne 0) || !($rollout_status =~ "successfully rolled out") ]];
then echo "ERROR: $rc"; exit; fi

#### PATCH CONTROLLER DEPLOYMENT ####
kubectl patch deployment  --namespace $ns $c_dep -p "$(cat controller.patch.yml)"
rc=$?; if [ $rc -ne 0 ]; then echo "ERROR: $rc"; exit; fi

rollout_status=$(kubectl rollout status --namespace $ns  deployment/$c_dep)
rc=$?; if [[ ($rc -ne 0) || !($rollout_status =~ "successfully rolled out") ]];
then echo "ERROR: $rc"; exit; fi

################################################################
# STEP: Remove Stale Controller Replicaset                     #
#                                                              # 
# NOTES: This step is applicable upon label selector updates,  #
# where the deployment creates orphaned replicasets            #
################################################################
kubectl delete rs $c_rs --namespace $ns
kubectl delete rs $r_rs --namespace $ns


