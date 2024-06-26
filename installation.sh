############################################################################################################################################
#--[1]- Basic Requirements
############################################################################################################################################

hostnamectl set-hostname <HOST_NAME>
sudo nano /etc/hosts 

apt-get install -y iputils-ping 
apt-get install -y net-tools 
sudo apt-get install nano

#!/bin/bash
#----------------------------------------------------------------------------------------------------------------------------------------
#--[1.1]- Modules 
tee /etc/modules-load.d/containerd.conf <<EOF
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
 
#--/etc/modules-load.d
#--overlay: pod network abstraction 
#--br_netfilter: bridge netfilter support - required for networking and policy
 
#--[1.2]- Force IPv4 and IPv6 traffic to pass through iptables. 
 
#-- Reason: Required for for most of CNI and Kubernetes networking policies to eable IPv4 and IPv6 traffic to be passed to iptables chains.
#--         Kubernetes requires that packets traversing a network bridge are processed for filtering and for port forwarding. 
#--         To achieve this, tunable parameters in the kernel bridge module are automatically set when the kubeadm package is installed and a 
#--         sysctl file is created at /etc/sysctl.d/99-kubernetes-cri.conf that contains the following lines: 
 
tee /etc/sysctl.d/99-kubernetes-cri.conf <<EOT
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOT
 
#--sysctl is used for modifying linux kernel variable.
#--sysctl -a command can be used to check all values.
sudo sysctl --system
 
#--[1.3]- Disable firewall 
sudo ufw disable
 
#--[1.4]- Disable swap  
sudo swapoff -a  
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab  

#--[1.5]- Install  necessary 
apt-get update  
apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common 
 
############################################################################################################################################
#--[2]- Install containerd
############################################################################################################################################
#--[2.1]- containerd installation
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/docker.gpg
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"

sudo apt update 
sudo apt install -y containerd.io 
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
 
#--[2.2]- Start and enable service 
sudo systemctl restart containerd
sudo systemctl enable containerd

############################################################################################################################################
#--[3]- Install Kubectl, Kubeadm and Kubelet
############################################################################################################################################
#--[3.1]- Add keys and repo 
curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg  
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"  

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.28/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list 


#--apt-cache policy kubelet | head -n 20 
#--[3.2]- Install 
sudo apt update 
sudo apt install -y kubelet kubeadm kubectl 
 
#--[3.3]- Stop automatic update 
apt-mark hold kubelet kubeadm kubectl  
 
#-----------------------------------------------------------------------------------------------------------------------------------------

############################################################################################################################################
#--[4]- Validation
############################################################################################################################################
 
#--[4.1]- Check memory 
free -m  

#--[4.2]- Check ufw 
sudo ufw status 
 
############################################################################################################################################
#--[5]- Initilize
############################################################################################################################################
 
#--[5.1]- Init (The main)
kubeadm init --pod-network-cidr 10.10.0.0/16 --node-name kcontrol

#--Follow the instructions in the output and paste the join command here
 
#--[5.2]- Join command can be generated 
kubeadm token create --print-join-command  
 
 
############################################################################################################################################
#--[6]- Add node 
############################################################################################################################################
#--With above command, you can add nodes. 
 
############################################################################################################################################
#--[7]- Setup CNI 
############################################################################################################################################
#--Install Weave   
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml 

############################################################################################################################################
#--[8]- Connect to pod 
############################################################################################################################################
#--Connect to pod
kubectl get nodes 
kubectl get pods -o wide --all-namespaces  
kubectl exec -it <Paste_pod_name_here> -- sh

############################################################################################################################################
#--[9]- Install Kubernetes Dashboard 
############################################################################################################################################
 
#--[9.1]- Install dashboard 
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
 
#--[9.2]- Configure Kubernetes dashboard  
kubectl create sa kube-ds-viewer -n kube-system 
kubectl create sa kube-ds-editor -n kube-system 
kubectl create sa kube-ds-admin -n kube-system 

#--[9.3]- Roles granting. Dashboard will appear blank otherwise  
kubectl create clusterrolebinding kube-ds-editor-role-binding --clusterrole=edit --user=system:serviceaccount:kube-system:kube-ds-editor 
kubectl create clusterrolebinding kube-ds-viewer-role-binding --clusterrole=view --user=system:serviceaccount:kube-system:kube-ds-viewer 
kubectl create clusterrolebinding kube-ds-admin-role-binding --clusterrole=admin --user=system:serviceaccount:kube-system:kube-ds-admin 
kubectl create clusterrolebinding serviceaccounts-cluster-admin --clusterrole=cluster-admin  --group=system:serviceaccounts  
 
 
#--[9.4]- Start proxy 
kubectl proxy
 
#--[9.5]- Connect in browser 
http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/ 
 
#--[9.6]- Then run below to generate the key --#  
kubectl create token kube-ds-viewer -n kube-system 

############################################################################################################################################
#--[10]- necessary commands 
############################################################################################################################################
#--[10.1]- Create nginx app 
kubectl create deployment nginx-app --image=nginx --replicas=2

#--[10.2]- Check status 
kubectl get deployment nginx-app

kubectl expose deployment nginx-app --type=NodePort --port=80
kubectl describe svc nginx-app
 
############################################################################################################################################
#--[11]- necessary commands 
############################################################################################################################################
kubectl get nodes 
kubectl get pods -o wide --all-namespaces  
journalctl -xeu kubelet  
kubectl get pods -o wide --all-namespaces 
kubectl get all -A 
 
 
 

