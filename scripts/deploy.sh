number=$1
clsname=$2

if hostname -i; then
  myip=$(hostname -i)
else
  myip=$(ipconfig getifaddr en0)
fi

cat << EOF > kind-${clsname}.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 6443
    hostPort: ${number}000
  - containerPort: ${number}2000
    hostPort: ${number}2000
    protocol: TCP
networking:
  disableDefaultCNI: true
kubeadmConfigPatches:
- |
  apiVersion: kubeadm.k8s.io/v1beta2
  kind: ClusterConfiguration
  metadata:
    name: config
  networking:
    serviceSubnet: "10.96.0.1/12"
    podSubnet: "192.168.128.0/17"
- |
  kind: InitConfiguration
  nodeRegistration:
    kubeletExtraArgs:
      node-labels: "topology.kubernetes.io/region=us-east-1,topology.kubernetes.io/zone=us-east-1c"
EOF

kind create cluster --name ${clsname} --config kind-${clsname}.yaml
kubectl config rename-context kind-${clsname} ${clsname}

ipkind=$(docker inspect ${clsname}-control-plane | jq -r '.[0].NetworkSettings.Networks.kind.IPAddress')
networkkind=$(echo ${ipkind} | sed 's/.$//')

kubectl config set-cluster ${clsname} --server=https://${myip}:${number}000 --insecure-skip-tls-verify=true

kubectl --context=${clsname} apply -f https://docs.projectcalico.org/v3.15/manifests/calico.yaml
kubectl --context=${clsname} -n kube-system set env daemonset/calico-node FELIX_IGNORELOOSERPF=true

kubectl --context=${clsname} apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/namespace.yaml
kubectl --context=${clsname} apply -f https://raw.githubusercontent.com/metallb/metallb/v0.9.3/manifests/metallb.yaml
kubectl --context=${clsname} create secret generic -n metallb-system memberlist --from-literal=secretkey="$(openssl rand -base64 128)"

cat << EOF > metallb-${clsname}.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - ${networkkind}2${number}0-${networkkind}2${number}9
EOF

kubectl --context=${clsname} apply -f metallb-${clsname}.yaml
